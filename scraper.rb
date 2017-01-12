#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'csv'
require 'pry'
require 'scraped'
require 'scraperwiki'
require 'combine_popolo_memberships'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

def noko_for(url)
  Nokogiri::XML(open(url).read)
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
      start_date:  mem.attr('fromdate'),
      end_date:    mem.attr('todate').sub('9999-12-31', ''),
    }.merge(aph_data)

    unless (wp = @wp_link.xpath("//personinfo[@id='#{id}']")).empty?
      person[:wikipedia] = wp.attr('wikipedia_url').text
      person[:wikipedia_name] = wp.attr('wikipedia_url').text.split('/').last.tr('_', ' ')
    end

    data = CombinePopoloMemberships.combine(id: [person], term: @terms)
    ScraperWiki.save_sqlite(%i(id term start_date), data)
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
