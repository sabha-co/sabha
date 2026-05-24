require "test_helper"

class SsrfProtectionTest < ActiveSupport::TestCase
  test "blocks loopback addresses" do
    stub_dns_resolution("127.0.0.1")
    assert_nil SsrfProtection.resolve_public_ip("localhost")
  end

  test "blocks RFC1918 private addresses" do
    { "10.0.0.1" => "ten.example.com",
      "172.16.0.1" => "twelve.example.com",
      "192.168.1.1" => "sixteen.example.com" }.each do |ip, host|
      stub_dns_resolution(ip)
      assert_nil SsrfProtection.resolve_public_ip(host), "Expected #{ip} to be blocked"
    end
  end

  test "blocks link-local addresses (AWS metadata endpoint)" do
    stub_dns_resolution("169.254.169.254")
    assert_nil SsrfProtection.resolve_public_ip("metadata.example.com")
  end

  test "blocks carrier-grade NAT addresses" do
    stub_dns_resolution("100.64.0.1")
    assert_nil SsrfProtection.resolve_public_ip("cgnat.example.com")
  end

  test "blocks benchmark testing addresses" do
    stub_dns_resolution("198.18.0.1")
    assert_nil SsrfProtection.resolve_public_ip("benchmark.example.com")
  end

  test "blocks broadcast addresses" do
    stub_dns_resolution("0.0.0.1")
    assert_nil SsrfProtection.resolve_public_ip("broadcast.example.com")
  end

  test "allows public addresses" do
    stub_dns_resolution("93.184.216.34")
    assert_equal "93.184.216.34", SsrfProtection.resolve_public_ip("example.com")
  end

  test "returns first public IP when multiple addresses resolve" do
    stub_dns_resolution("10.0.0.1", "93.184.216.34", "192.168.1.1")
    assert_equal "93.184.216.34", SsrfProtection.resolve_public_ip("multi.example.com")
  end

  # Block all ipv4_mapped? regardless of the inner address, since DNS never
  # returns this format legitimately. The public-IP case is the load-bearing
  # security claim; the private and link-local cases are demonstrative.
  test "blocks IPv4-mapped IPv6 addresses" do
    { "::ffff:192.168.1.1"    => "mapped-private.example.com",
      "::ffff:169.254.169.254" => "mapped-metadata.example.com",
      "::ffff:93.184.216.34"   => "mapped-public.example.com" }.each do |ip, host|
      stub_dns_resolution(ip)
      assert_nil SsrfProtection.resolve_public_ip(host), "Expected #{ip} to be blocked"
    end
  end

  # The IPv4-compatible link-local case is the reported AWS metadata bypass
  # that motivated blocking all ipv4_compat? regardless of inner address.
  test "blocks IPv4-compatible IPv6 addresses including the reported AWS metadata bypass" do
    { "::192.168.1.1"    => "compat-private.example.com",
      "::169.254.169.254" => "compat-metadata.example.com",
      "::93.184.216.34"   => "compat-public.example.com" }.each do |ip, host|
      stub_dns_resolution(ip)
      assert_nil SsrfProtection.resolve_public_ip(host), "Expected #{ip} to be blocked"
    end
  end

  test "resolve! raises Unresolvable when no address resolves" do
    stub_dns_resolution
    assert_raises SsrfProtection::Unresolvable do
      SsrfProtection.resolve!("nonexistent.example.com")
    end
  end

  test "resolve! raises PrivateAddress when only blocked addresses resolve" do
    stub_dns_resolution("192.168.1.1")
    assert_raises SsrfProtection::PrivateAddress do
      SsrfProtection.resolve!("private.example.com")
    end
  end

  test "resolve! returns the IP for public hostnames" do
    stub_dns_resolution("93.184.216.34")
    assert_equal "93.184.216.34", SsrfProtection.resolve!("example.com")
  end

  test "blocked_address? treats unparseable inputs as blocked" do
    assert SsrfProtection.blocked_address?("not-an-ip")
    assert SsrfProtection.blocked_address?("")
  end
end
