#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
require 'open-uri'
require 'colorize'

require 'pry'
require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

def noko_for(url)
  Nokogiri::XML(open(url).read)
  # Nokogiri::HTML(open(url).read, nil, 'utf-8')
end

def overlap(mem, term)
  mS = mem[:start_date].to_s.empty?  ? '0000-00-00' : mem[:start_date]
  mE = mem[:end_date].to_s.empty?    ? '9999-12-31' : mem[:end_date]
  tS = term[:start_date].to_s.empty? ? '0000-00-00' : term[:start_date]
  tE = term[:end_date].to_s.empty?   ? '9999-12-31' : term[:end_date]

  return unless mS < tE && mE > tS
  (s, e) = [mS, mE, tS, tE].sort[1,2]
  return { 
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
        email: aph.xpath('./@mp_email').text,
        website: aph.xpath('./@mp_website').text,
        facebook: aph.xpath('./@mp_facebook_url').text,
        twitter: aph.xpath('./@mp_twitter_url').text,
      }
    end

    person = { 
      id: id.split("/").last,
      name: "%s %s" % [mem.attr('firstname'), mem.attr('lastname')],
      sort_name: "%s, %s" % [mem.attr('lastname'), mem.attr('firstname')],
      given_name: mem.attr('firstname'),
      family_name: mem.attr('lastname'),
      area: mem.attr('division'),
      party: mem.attr('party'),
      source: url,
    }.merge(aph_data)

    unless (wp = @wp_link.xpath("//personinfo[@id='#{id}']")).empty?
      person[:wikipedia] = wp.attr('wikipedia_url').text
      person[:wikipedia_name] = wp.attr('wikipedia_url').text.split("/").last.gsub('_', ' ')
    end

    mem = { 
      start_date: mem.attr('fromdate'),
      end_date: mem.attr('todate').sub('0015-','2015-'), # https://github.com/openaustralia/openaustralia/issues/597
    }

    @terms.each do |term|
      range = overlap(mem, term) or next
      row = person.merge(range).merge({ term: term[:id] })
      ScraperWiki.save_sqlite([:id, :term, :start_date], row)
    end

  end
end

require 'csv'
termdates = <<EODATA
id,name,start_date,end_date
35,35th Parliament,1987-07-11,1990-03-24
36,36th Parliament,1990-03-24,1993-03-13
37,37th Parliament,1993-03-13,1996-03-02
38,38th Parliament,1996-03-02,1998-10-03
39,39th Parliament,1998-10-03,2001-11-10
40,40th Parliament,2001-11-10,2004-10-09
41,41st Parliament,2004-10-09,2007-11-24
42,42nd Parliament,2007-11-24,2010-08-21
43,43rd Parliament,2010-08-21,2013-09-07
44,44th Parliament,2013-09-07,2016-06-05
45,45th Parliament,2016-02-07,
EODATA
@terms = CSV.parse(termdates, headers: true, header_converters: :symbol).map(&:to_hash)
ScraperWiki.save_sqlite([:id], @terms, 'terms')

@persons = noko_for('http://data.openaustralia.org/members/people.xml')
@aphinfo = noko_for('http://data.openaustralia.org/members/websites.xml')
@wp_link = noko_for('http://data.openaustralia.org/members/wikipedia-commons.xml')

scrape_list('http://data.openaustralia.org/members/senators.xml')
