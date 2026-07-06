package agent

import "testing"

func TestParseCPUTimesAndUsage(t *testing.T) {
	before := "cpu  100 0 50 850 0 0 0 0 0 0\ncpu0 50 0 25 425 0 0 0 0 0 0\n"
	after := "cpu  150 0 75 875 0 0 0 0 0 0\ncpu0 75 0 35 440 0 0 0 0 0 0\n"
	prev, _, err := parseCPUTimes(before)
	if err != nil {
		t.Fatal(err)
	}
	curr, cores, err := parseCPUTimes(after)
	if err != nil {
		t.Fatal(err)
	}
	if len(cores) != 1 {
		t.Fatalf("expected one core, got %d", len(cores))
	}
	if got := cpuUsagePercent(prev, curr); got != 75 {
		t.Fatalf("expected 75%% cpu, got %.2f", got)
	}
}

func TestParseMeminfo(t *testing.T) {
	mem, swap, err := parseMeminfo(`
MemTotal:        1000 kB
MemFree:          100 kB
MemAvailable:     250 kB
Buffers:           50 kB
Cached:           150 kB
SwapTotal:        500 kB
SwapFree:         125 kB
`)
	if err != nil {
		t.Fatal(err)
	}
	if mem.TotalBytes != 1024000 || mem.AvailableBytes != 256000 || mem.UsedBytes != 768000 {
		t.Fatalf("unexpected memory stats: %+v", mem)
	}
	if swap.UsedBytes != 384000 {
		t.Fatalf("unexpected swap stats: %+v", swap)
	}
}

func TestParseLoadavg(t *testing.T) {
	load, err := parseLoadavg("1.25 0.50 0.10 1/100 1234")
	if err != nil {
		t.Fatal(err)
	}
	if load.One != 1.25 || load.Five != 0.50 || load.Fifteen != 0.10 {
		t.Fatalf("unexpected load: %+v", load)
	}
}

func TestParseNetDev(t *testing.T) {
	counters, err := parseNetDev(`
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 1 0 0 0 0 0 0 0 2 0 0 0 0 0 0 0
  eth0: 1000 0 0 0 0 0 0 0 2500 0 0 0 0 0 0 0
`)
	if err != nil {
		t.Fatal(err)
	}
	if len(counters) != 1 || counters["eth0"].Rx != 1000 || counters["eth0"].Tx != 2500 {
		t.Fatalf("unexpected counters: %+v", counters)
	}
}
