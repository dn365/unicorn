# Copyright (c) 2009 Eric Wong
# You can redistribute it and/or modify it under the same terms as Ruby.

if RUBY_VERSION =~ /1\.9/
  warn "#$0 current broken under Ruby 1.9 with Rack"
  exit 0
end

require 'test/test_helper'
begin
  require 'rack'
  require 'rack/lint'
rescue LoadError
  warn "Unable to load rack, skipping test"
  exit 0
end

include Unicorn

class RequestTest < Test::Unit::TestCase

  class MockRequest < StringIO
    def unicorn_peeraddr
      '666.666.666.666'
    end
  end

  def setup
    @request = HttpRequest.new(Logger.new($stderr))
    @app = lambda do |env|
      [ 200, { 'Content-Length' => '0', 'Content-Type' => 'text/plain' }, [] ]
    end
    @lint = Rack::Lint.new(@app)
  end

  def test_options
    client = MockRequest.new("OPTIONS * HTTP/1.1\r\n" \
                             "Host: foo\r\n\r\n")
    res = env = nil
    assert_nothing_raised { env = @request.read(client) }
    assert_equal '*', env['REQUEST_PATH']
    assert_equal '*', env['PATH_INFO']
    assert_equal '*', env['REQUEST_URI']

    # assert_nothing_raised { res = @lint.call(env) } # fails Rack lint
  end

  def test_full_url_path
    client = MockRequest.new("GET http://e:3/x?y=z HTTP/1.1\r\n" \
                             "Host: foo\r\n\r\n")
    res = env = nil
    assert_nothing_raised { env = @request.read(client) }
    assert_equal '/x', env['REQUEST_PATH']
    assert_equal '/x', env['PATH_INFO']
    assert_nothing_raised { res = @lint.call(env) }
  end

  def test_rack_lint_get
    client = MockRequest.new("GET / HTTP/1.1\r\nHost: foo\r\n\r\n")
    res = env = nil
    assert_nothing_raised { env = @request.read(client) }
    assert_equal '666.666.666.666', env['REMOTE_ADDR']
    assert_nothing_raised { res = @lint.call(env) }
  end

  def test_rack_lint_put
    client = MockRequest.new(
      "PUT / HTTP/1.1\r\n" \
      "Host: foo\r\n" \
      "Content-Length: 5\r\n" \
      "\r\n" \
      "abcde")
    res = env = nil
    assert_nothing_raised { env = @request.read(client) }
    assert ! env.include?(:http_body)
    assert_nothing_raised { res = @lint.call(env) }
  end

  def test_rack_lint_big_put
    count = 100
    bs = 0x10000
    buf = (' ' * bs).freeze
    length = bs * count
    client = Tempfile.new('big_put')
    def client.unicorn_peeraddr
      '1.1.1.1'
    end
    client.syswrite(
      "PUT / HTTP/1.1\r\n" \
      "Host: foo\r\n" \
      "Content-Length: #{length}\r\n" \
      "\r\n")
    count.times { assert_equal bs, client.syswrite(buf) }
    assert_equal 0, client.sysseek(0)
    res = env = nil
    assert_nothing_raised { env = @request.read(client) }
    assert ! env.include?(:http_body)
    assert_equal length, env['rack.input'].size
    count.times { assert_equal buf, env['rack.input'].read(bs) }
    assert_nil env['rack.input'].read(bs)
    assert_nothing_raised { env['rack.input'].rewind }
    assert_nothing_raised { res = @lint.call(env) }
  end

end

