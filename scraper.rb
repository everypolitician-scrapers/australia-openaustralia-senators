#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'csv'
require 'pry'
require 'scraped'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

def noko_for(url)
  Nokogiri::XML(open(url).read)
end

def overlap(mem, term)
  mS = mem[:start_date].to_s.empty?  ? '0000-00-00' : mem[:start_date]
  mE = mem[:end_date].to_s.empty?    ? '9999-12-31' : mem[:end_date]
  tS = term[:start_date].to_s.empty? ? '0000-00-00' : term[:start_date]
  tE = term[:end_date].to_s.empty?   ? '9999-12-31' : term[:end_date]

  return unless mS < tE && mE > tS
  (s, e) = [mS, mE, tS, tE].sort[1, 2]
  {
    start_date: s == '0000-00-00' ? nil : s,
    end_date:   e == '9999-12-31' ? nil : e,
  }
end

def scrape_list(url)
  noko = noko_for(url)
  noko.xpath('//members/member').each do |mem|
    membership_id = mem.attr('id')
    id = @persons.xpath("//person[office[@id='#{membership_id}']]/@id").text
    aph_data = {}
    unless (aph = @aphinfo.xpath("//personinfo[@id='#{id}']")).empty?
      aph_data = {
        identifier__aph: aph.attr('aph_url').text[/MPID=(.*)/, 1],
        email:           aph.xpath('./@mp_email').text,
        website:         aph.xpath('./@mp_website').text,
        facebook:        aph.xpath('./@mp_facebook_url').text,
        twitter:         aph.xpath('./@mp_twitter_url').text,
      }
    end

    person = {
      id:          id.split('/').last,
      name:        '%s %s' % [mem.attr('firstname'), mem.attr('lastname')],
      sort_name:   '%s, %s' % [mem.attr('lastname'), mem.attr('firstname')],
      given_name:  mem.attr('firstname'),
      family_name: mem.attr('lastname'),
      area:        mem.attr('division'),
      party:       mem.attr('party'),
      source:      url,
    }.merge(aph_data)

    unless (wp = @wp_link.xpath("//personinfo[@id='#{id}']")).empty?
      person[:wikipedia] = wp.attr('wikipedia_url').text
      person[:wikipedia_name] = wp.attr('wikipedia_url').text.split('/').last.tr('_', ' ')
    end

    mem = {
      start_date: mem.attr('fromdate'),
      end_date:   mem.attr('todate').sub('0015-', '2015-'), # https://github.com/openaustralia/openaustralia/issues/597
    }

    @terms.each do |term|
      range = overlap(mem, term) or next
      row = person.merge(range).merge(term: term[:id])
      ScraperWiki.save_sqlite(%i(id term start_date), row)
    end
  end
end

termdates = open('https://raw.githubusercontent.com/everypolitician/everypolitician-data/'\
                  'master/data/Australia/Senate/sources/manual/terms.csv').read
@terms = CSV.parse(termdates, headers: true, header_converters: :symbol).map(&:to_hash)

@persons = noko_for('http://data.openaustralia.org/members/people.xml')
@aphinfo = noko_for('http://data.openaustralia.org/members/websites.xml')
@wp_link = noko_for('http://data.openaustralia.org/members/wikipedia-commons.xml')

ScraperWiki.sqliteexecute('DELETE FROM data') rescue nil
scrape_list('http://data.openaustralia.org/members/senators.xml')
