require "test_helper"

class RestrictedHTTP::PrivateNetworkGuardTest < ActiveSupport::TestCase
  Guard = RestrictedHTTP::PrivateNetworkGuard

  # --- resolve_public_ip! (raising) -------------------------------------------------

  test "resolve_public_ip! returns the first public address" do
    stub_dns_resolution("93.184.216.34")
    assert_equal "93.184.216.34", Guard.resolve_public_ip!("example.com")
  end

  test "resolve_public_ip! prefers IPv4 and skips blocked addresses" do
    stub_dns_resolution("10.0.0.1", "93.184.216.34", "192.168.1.1")
    assert_equal "93.184.216.34", Guard.resolve_public_ip!("multi.example.com")
  end

  test "resolve_public_ip! raises Violation when the host resolves only to blocked addresses" do
    stub_dns_resolution("192.168.1.1")
    assert_raises Guard::Violation do
      Guard.resolve_public_ip!("private.example.com")
    end
  end

  test "resolve_public_ip! raises Unresolvable, not Violation, when the host resolves to nothing" do
    stub_dns_resolution
    assert_raises Surfguard::Unresolvable do
      Guard.resolve_public_ip!("nonexistent.example.com")
    end
  end

  # --- resolve_public_ip (soft) ------------------------------------------

  test "resolve_public_ip returns the public address" do
    stub_dns_resolution("93.184.216.34")
    assert_equal "93.184.216.34", Guard.resolve_public_ip("example.com")
  end

  test "resolve_public_ip returns nil for a blocked host" do
    stub_dns_resolution("169.254.169.254") # AWS metadata endpoint
    assert_nil Guard.resolve_public_ip("metadata.example.com")
  end

  test "resolve_public_ip returns nil for an unresolvable host" do
    stub_dns_resolution
    assert_nil Guard.resolve_public_ip("nonexistent.example.com")
  end

  test "resolve_public_ip returns nil for a nil host" do
    assert_nil Guard.resolve_public_ip(nil)
  end

  # --- the surfguard policy is enforced at this boundary -----------------

  test "blocks the address ranges Sabha relies on" do
    {
      "127.0.0.1"       => "loopback",
      "10.0.0.1"        => "RFC1918",
      "169.254.169.254" => "link-local / cloud metadata",
      "100.64.0.1"      => "carrier-grade NAT",
      "198.18.0.1"      => "benchmark",
      "::ffff:192.168.1.1" => "IPv4-mapped private"
    }.each do |ip, label|
      stub_dns_resolution(ip)
      assert_nil Guard.resolve_public_ip("host.example.com"), "expected #{ip} (#{label}) to be blocked"
    end
  end
end
