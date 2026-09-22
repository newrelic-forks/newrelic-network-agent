package snmp

import (
	"context"
	"errors"
	"net"
	"sync"
	"syscall"
	"time"

	"github.com/google/gopacket/macs"
	"github.com/mostlygeek/arp"
)

// maxConcurrentProbes bounds scanCIDR's goroutine fan-out. Deliberately not tied to
// conf.Disco.Threads -- that knob already means something else (how many CIDRs from
// conf.Disco.Cidrs are scanned in parallel, via disco.go's own ctl channel), and is
// typically small (default 4). Reusing it here would make every single-CIDR scan
// absurdly slow. This bound is purely about not launching one goroutine (plus a
// reverse DNS lookup and a TCP dial each) per address in one CIDR at once -- a
// configured /16 would otherwise be 65536 goroutines with no cap at all.
const maxConcurrentProbes = 256

// netScanResult describes what was learned about one IP during a network scan.
type netScanResult struct {
	Host         net.IP
	MAC          string
	Manufacturer string
	Name         string
	Latency      time.Duration
}

func (r netScanResult) IsHostUp() bool {
	return r.Latency > -1
}

// scanCIDR probes every host in cidr: an ARP-table MAC lookup, a MAC-prefix
// vendor lookup, a reverse DNS lookup, and a TCP dial to port 1 to gauge
// liveness/latency. Up to maxConcurrentProbes goroutines in flight at once.
func scanCIDR(ctx context.Context, cidr string, timeout time.Duration) ([]netScanResult, error) {
	ip, ipnet, err := net.ParseCIDR(cidr)
	if err != nil {
		return nil, err
	}
	ip = ip.Mask(ipnet.Mask)

	var wg sync.WaitGroup
	var mux sync.Mutex
	results := []netScanResult{}
	sem := make(chan struct{}, maxConcurrentProbes)

	for ; ipnet.Contains(ip); incrementIP(ip) {
		select {
		case <-ctx.Done():
			wg.Wait()
			return results, ctx.Err()
		case sem <- struct{}{}:
		}

		target := make(net.IP, len(ip))
		copy(target, ip)

		wg.Add(1)
		go func(target net.IP) {
			defer wg.Done()
			defer func() { <-sem }()
			r := probeHost(target, timeout)
			mux.Lock()
			results = append(results, r)
			mux.Unlock()
		}(target)
	}
	wg.Wait()

	return results, nil
}

func probeHost(ip net.IP, timeout time.Duration) netScanResult {
	r := netScanResult{Host: ip, Latency: -1}

	if macStr := arp.Search(ip.String()); macStr != "" && macStr != "00:00:00:00:00:00" {
		if mac, err := net.ParseMAC(macStr); err == nil {
			r.MAC = mac.String()

			prefix := [3]byte{mac[0], mac[1], mac[2]}
			if manufacturer, ok := macs.ValidMACPrefixMap[prefix]; ok {
				r.Manufacturer = manufacturer
			}

			if addrs, err := net.LookupAddr(ip.String()); err == nil && len(addrs) > 0 {
				r.Name = addrs[0]
			}
		}
	}

	start := time.Now()
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(ip.String(), "1"), timeout)
	switch {
	case err == nil:
		// Connected outright -- definitely up.
		r.Latency = time.Since(start)
		conn.Close()
	case errors.Is(err, syscall.ECONNREFUSED):
		// Actively refused: the host sent back a RST, so it's up even though
		// nothing is listening on this deliberately-unlikely-to-be-open port.
		r.Latency = time.Since(start)
	default:
		// Anything else -- a timeout (no response at all), "network is
		// unreachable"/"no route to host" (no response from *this* host
		// specifically), or a local resource error like "too many open files"
		// during a large scan -- is not evidence the host is up. The previous
		// !strings.Contains(err.Error(), "timeout") check got this backwards:
		// it treated every one of these as a live host, so resource exhaustion
		// alone could make nearly an entire CIDR appear to respond.
	}

	return r
}

// incrementIP walks ip to the next address in place, matching furious's
// TargetIterator semantics (wraps within the byte slice's own length).
func incrementIP(ip net.IP) {
	for j := len(ip) - 1; j >= 0; j-- {
		ip[j]++
		if ip[j] > 0 {
			break
		}
	}
}
