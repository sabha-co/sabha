module DnsTestHelper
  # Surfguard resolves hostnames through Resolv.getaddresses, so stub that.
  # (Numeric-literal hosts go through Socket.getaddrinfo instead and don't need
  # a stub -- the tests here all use hostnames.)
  def stub_dns_resolution(*ips)
    Resolv.stubs(:getaddresses).returns(ips)
  end

  # Stubs a sequence of DNS resolutions across successive lookups. Use to
  # simulate DNS rebinding: pass [public_ip] then [private_ip] to make the first
  # resolve return the safe IP that passes validation, and the second (rebound)
  # call return the malicious one.
  def stub_dns_resolution_sequence(*ip_sets)
    expectation = Resolv.stubs(:getaddresses)
    ip_sets.each do |ips|
      expectation = expectation.returns(Array(ips)).then
    end
  end
end
