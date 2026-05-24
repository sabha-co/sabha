module DnsTestHelper
  def stub_dns_resolution(*ips)
    dns_mock = mock("dns")
    dns_mock.stubs(:each_address).multiple_yields(*ips)
    Resolv::DNS.stubs(:open).yields(dns_mock)
  end

  # Stubs a sequence of DNS resolutions across successive Resolv::DNS.open
  # calls. Use to simulate DNS rebinding: pass [public_ip] then [private_ip]
  # to make the first resolve return the safe IP that passes validation, and
  # the second (rebound) call return the malicious one.
  def stub_dns_resolution_sequence(*ip_sets)
    expectation = Resolv::DNS.stubs(:open)
    ip_sets.each do |ips|
      dns_mock = mock("dns")
      dns_mock.stubs(:each_address).multiple_yields(*Array(ips))
      expectation = expectation.yields(dns_mock).then
    end
  end
end
