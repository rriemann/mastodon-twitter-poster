require 'test_helper'
require 'mastodon_user_processor'

class MastodonUserProcessorTest < ActiveSupport::TestCase
  test 'boost as link' do
    user = create(:user_with_mastodon_and_twitter, masto_domain: 'mastodon.xyz')

    stub_request(:get, 'https://mastodon.xyz/api/v1/statuses/6901463').to_return(web_fixture('mastodon_boost.json'))
    t = user.mastodon_client.status(6901463)
    text = "Boosted: #{t.url}"

    mastodon_user_processor = MastodonUserProcessor.new(t, user)
    mastodon_user_processor.expects(:should_post).returns(true)
    mastodon_user_processor.expects(:tweet).with(text).times(1).returns(nil)
    mastodon_user_processor.boost_as_link
  end

  test 'process toot - direct toot' do
    user = create(:user_with_mastodon_and_twitter, masto_domain: 'mastodon.xyz')

    stub_request(:get, 'https://mastodon.xyz/api/v1/statuses/7706182').to_return(web_fixture('mastodon_direct_toot.json'))
    t = user.mastodon_client.status(7706182)

    MastodonUserProcessor.expects(:process_boost).times(0)
    MastodonUserProcessor.expects(:process_reply).times(0)
    MastodonUserProcessor.expects(:process_mention).times(0)
    MastodonUserProcessor.expects(:process_normal_toot).times(0)

    mastodon_user_processor = MastodonUserProcessor.new(t, user)
    mastodon_user_processor.expects(:posted_by_crossposter).returns(false)

    mastodon_user_processor.process_toot
  end

  test 'process toot - posted by the crossposter' do
    user = create(:user_with_mastodon_and_twitter, masto_domain: 'mastodon.xyz')

    stub_request(:get, 'https://mastodon.xyz/api/v1/statuses/98894252337740537').to_return(web_fixture('mastodon_crossposted_toot.json'))
    t = user.mastodon_client.status(98894252337740537)

    MastodonUserProcessor.expects(:process_boost).times(0)
    MastodonUserProcessor.expects(:process_reply).times(0)
    MastodonUserProcessor.expects(:process_mention).times(0)
    MastodonUserProcessor.expects(:process_normal_toot).times(0)

    mastodon_user_processor = MastodonUserProcessor.new(t, user)
    mastodon_user_processor.process_toot
  end

  test 'process normal toot' do
    user = create(:user_with_mastodon_and_twitter, masto_domain: 'mastodon.xyz')
    text = 'Test.'

    stub_request(:get, 'https://mastodon.xyz/api/v1/statuses/7692449').to_return(web_fixture('mastodon_toot.json'))
    t = user.mastodon_client.status(7692449)

    toot_transformer = mock()
    TootTransformer.expects(:new).with(280).returns(toot_transformer)
    toot_transformer.expects(:transform).with(t.text_content, t.url, 'https://mastodon.xyz', false).returns(t.text_content)
    mastodon_user_processor = MastodonUserProcessor.new(t, user)
    mastodon_user_processor.expects(:should_post).returns(true)
    mastodon_user_processor.expects(:tweet).with(text, {}).times(1).returns(nil)
    mastodon_user_processor.expects(:toot_content_to_post).returns(t.text_content)
    mastodon_user_processor.expects(:upload_media).returns({})

    mastodon_user_processor.process_normal_toot
  end

  test 'tweet' do
    user = create(:user_with_mastodon_and_twitter)

    text = 'Oh yeah!'
    tweet_id = 926053415448469505
    masto_id = 98392839283
    medias = []
    possibly_sensitive = false
    expected_status = Status.new(mastodon_client_id: user.mastodon.mastodon_client_id, tweet_id: tweet_id, masto_id: masto_id)

    stub_request(:post, 'https://api.twitter.com/1.1/statuses/update.json').to_return(web_fixture('twitter_update.json'))
    toot = mock()
    toot.expects(:id).returns(masto_id)
    MastodonUserProcessor.new(toot, user).tweet(text)
    ignored_attributes = %w(id created_at updated_at)
    assert_equal expected_status.attributes.except(*ignored_attributes), Status.last.attributes.except(*ignored_attributes)
  end

  test 'posted by the crossposter - boost not posted' do
    user = create(:user_with_mastodon_and_twitter, masto_domain: 'mastodon.xyz')

    stub_request(:get, 'https://mastodon.xyz/api/v1/statuses/6901463').to_return(web_fixture('mastodon_boost.json'))
    t = user.mastodon_client.status(6901463)

    refute MastodonUserProcessor.new(t, user).posted_by_crossposter
  end
  test 'posted by the crossposter - not posted' do
    user = create(:user_with_mastodon_and_twitter, masto_domain: 'mastodon.xyz')

    stub_request(:get, 'https://mastodon.xyz/api/v1/statuses/7692449').to_return(web_fixture('mastodon_toot.json'))
    t = user.mastodon_client.status(7692449)

    refute MastodonUserProcessor.new(t, user).posted_by_crossposter
  end
  test 'posted by the crossposter - link match' do
    user = create(:user_with_mastodon_and_twitter, masto_domain: 'mastodon.xyz')

    stub_request(:get, 'https://mastodon.xyz/api/v1/statuses/98894252337740537').to_return(web_fixture('mastodon_crossposted_toot.json'))
    t = user.mastodon_client.status(98894252337740537)

    assert MastodonUserProcessor.new(t, user).posted_by_crossposter
  end
  test 'posted by the crossposter - status in the database' do
    user = create(:user_with_mastodon_and_twitter, masto_domain: 'mastodon.xyz')

    stub_request(:get, 'https://mastodon.xyz/api/v1/statuses/7692449').to_return(web_fixture('mastodon_toot.json'))
    t = user.mastodon_client.status(7692449)

    status = create(:status, masto_id: t.id, mastodon_client: user.mastodon.mastodon_client)

    assert MastodonUserProcessor.new(t, user).posted_by_crossposter
  end

  test 'Recover from too big status' do
    user = create(:user_with_mastodon_and_twitter, masto_domain: 'mastodon.xyz')

    stub_request(:get, 'https://mastodon.xyz/api/v1/statuses/98974469120828056').to_return(web_fixture('masto_500_chars.json'))
    t = user.mastodon_client.status(98974469120828056)

    stub_request(:post, 'https://api.twitter.com/1.1/statuses/update.json').to_return(web_fixture('twitter_update_too_big.json'), web_fixture('twitter_update.json'))

    mastodon_user_processor = MastodonUserProcessor.new(t, user)
    mastodon_user_processor.process_toot
  end
end
