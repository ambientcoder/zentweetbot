# encoding: UTF-8

require 'rubygems'
require 'twitter'
require 'punkt-segmenter'
require 'twitter_init'
require 'variables'
require 'markov'
require 'htmlentities'
require 'uri'

source_tweets = []

$rand_limit ||= 10
$markov_index ||= 2

puts "random limit: #$rand_limit"
puts "markov index: #$markov_index"
puts "PARAMS: #{params}" if params.any?

unless params.key?("tweet")
  params["tweet"] = true
end

rand_key = rand($rand_limit)

CLOSING_PUNCTUATION = ['.', ';', ':', '?', '!', ',']

def random_closing_punctuation
  CLOSING_PUNCTUATION[rand(CLOSING_PUNCTUATION.length)]
end

HASHTAG = ['#discuss', '#change', '#strategy', '#power', '#politics', '#art' , '#repetition', '#conceptual', '#slow', '#zen', '#future', '#oblique']

def random_hashtag
  HASHTAG[rand(HASHTAG.length)]
end

def filtered_tweets(tweets)
  html_decoder = HTMLEntities.new
  include_urls = $include_urls || params["include_urls"]
  include_replies = $include_replies || params["include_replies"]
  source_tweets = tweets.map {|t| html_decoder.decode(t.text).gsub(/\b(RT|MT) .+/, '') }

  if !include_urls
    source_tweets = source_tweets.reject {|t| t =~ /(https?:\/\/)/ }
  end

  if !include_replies
    source_tweets = source_tweets.reject {|t| t =~ /^@/ }
  end

  source_tweets.each do |t| 
#    strip out twitter handles
    t.gsub!(/(@[\d\w_]+\s?)+/, '')
    t.gsub!(/[”“]/, '"')
    t.gsub!(/[‘’]/, "'")
    t.strip!
  end

  source_tweets
end

# randomly running only about 1 in $rand_limit times
unless rand_key == 0 || params["force"]
  puts "Not running this time (key: #{rand_key})"
else

client = Twitter::REST::Client.new do |config|
  config.consumer_key = $consumer_key
  config.consumer_secret = $consumer_secret
  config.access_token = $access_token
  config.access_token_secret = $access_token_secret
end

  # Fetch a thousand tweets
  begin
    user_tweets = client.user_timeline($source_account, :count => 200, :trim_user => true)
    max_id = user_tweets.last.id
    source_tweets += filtered_tweets(user_tweets)
  
    # Twitter only returns up to 3200 of a user timeline, includes retweets.
    17.times do
      user_tweets = client.user_timeline($source_account, :count => 200, :trim_user => true, :max_id => max_id - 1)
      puts "MAX_ID #{max_id} TWEETS: #{user_tweets.length}"
      break if user_tweets.last.nil?
      max_id = user_tweets.last.id
      source_tweets += filtered_tweets(user_tweets)
    end
  rescue => ex
    puts ex.message
  end
  
  puts "#{source_tweets.length} tweets found"

  if source_tweets.length == 0
    raise "Error fetching tweets from Twitter. Aborting."
  end
  
  markov = MarkovChainer.new($markov_index)

  tokenizer = Punkt::SentenceTokenizer.new(source_tweets.join(" "))  # init with corpus of all sentences

  source_tweets.each do |twt|
    next if twt.nil? || twt == ''
    sentences = tokenizer.sentences_from_text(twt, :output => :sentences_text)

    # sentences = text.split(/[.:;?!]/)

    # sentences.each do |sentence|
    #   next if sentence =~ /@/

    #   if sentence !~ /\p{Punct}$/
    #     sentence += "."
    #   end

    sentences.each do |sentence|
      next if sentence =~ /@/
      markov.add_sentence(sentence)
    end
  end
  
  tweet = nil
  
  10.times do
    tweet = markov.generate_sentence

    tweet_letters = tweet.gsub(/\P{Word}/, '')
    next if source_tweets.any? {|t| t.gsub(/\P{Word}/, '') =~ /#{tweet_letters}/ }

    # if rand(3) == 0 && tweet =~ /(in|to|from|for|with|by|our|of|your|around|under|beyond)\p{Space}\w+$/ 
    #   puts "Losing last word randomly"
    #   tweet.gsub(/\p{Space}\p{Word}+.$/, '')   # randomly losing the last word sometimes like horse_ebooks
    # end

    if tweet.length < 40 && rand(10) == 0
      puts "Short tweet. Adding another sentence randomly"
      next_sentence = markov.generate_sentence
      tweet_letters = next_sentence.gsub(/\P{Word}/, '')
      next if source_tweets.any? {|t| t.gsub(/\P{Word}/, '') =~ /#{tweet_letters}/ }

      tweet += random_closing_punctuation if tweet !~ /[.;:?!),'"}\]\u2026]$/
      tweet += " #{markov.generate_sentence}"
    end

    if !params["tweet"]
      puts "MARKOV: #{tweet}"
    end

    break if !tweet.nil? && tweet.length < 110
  end
  
  tweet += random_closing_punctuation if tweet !~ /[.;:?!),'"}\]\u2026]$/

# format http t co as http://t.co
  tweet.gsub!(/https?.*t co /, 'http://t.co/')

# remove trailing punctuation if tweet contains URLs
  tweet.gsub!(/\p{Punct}$/, '') if tweet =~ URI::regexp

# add a random hashtag for 1 in 4 tweets and if the tweet is less than 125 chars
  tweet += " #{random_hashtag}" if rand(3) == 0 && tweet.length < 125

  if params["tweet"]
    if !tweet.nil? && tweet != ''
      puts "TWEET: #{tweet}"
      client.update(tweet)
    else
      raise "ERROR: EMPTY TWEET"
    end
  else
    puts "DEBUG: #{tweet}"
  end
end

