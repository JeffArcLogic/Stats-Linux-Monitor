package agent

import (
	"os"
	"path/filepath"
	"testing"
)

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

func TestDiskUsageFromStatfsUsesAvailableBlocksForPressure(t *testing.T) {
	total, used, free, usage, ok := diskUsageFromStatfs(1000, 450, 400, 1024)
	if !ok {
		t.Fatal("expected disk stats")
	}
	if total != 1024000 {
		t.Fatalf("expected total bytes to keep filesystem size, got %d", total)
	}
	if used != 563200 {
		t.Fatalf("expected used bytes to exclude reserved blocks, got %d", used)
	}
	if free != 409600 {
		t.Fatalf("expected free bytes from available blocks, got %d", free)
	}
	if usage < 57.89 || usage > 57.90 {
		t.Fatalf("expected df-style usage around 57.89%%, got %.4f", usage)
	}
}

func TestReadSensorsFromHwmonAndThermalZones(t *testing.T) {
	root := t.TempDir()
	hwmon := filepath.Join(root, "hwmon", "hwmon0")
	thermal := filepath.Join(root, "thermal", "thermal_zone0")
	for _, dir := range []string{hwmon, thermal} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	files := map[string]string{
		filepath.Join(hwmon, "name"):        "coretemp\n",
		filepath.Join(hwmon, "temp1_label"): "Package id 0\n",
		filepath.Join(hwmon, "temp1_input"): "42500\n",
		filepath.Join(hwmon, "temp2_input"): "41000\n",
		filepath.Join(thermal, "type"):      "x86_pkg_temp\n",
		filepath.Join(thermal, "temp"):      "43000\n",
	}
	for path, contents := range files {
		if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	sensors := readSensorsFrom(
		filepath.Join(root, "hwmon", "hwmon*", "temp*_input"),
		filepath.Join(root, "thermal", "thermal_zone*", "temp"),
	)
	if len(sensors) != 3 {
		t.Fatalf("expected three sensors, got %+v", sensors)
	}
	if sensors[0].Name != "coretemp Package id 0" || sensors[0].TempCelsius != 42.5 {
		t.Fatalf("unexpected labeled hwmon sensor: %+v", sensors[0])
	}
	if sensors[1].Name != "coretemp temp2" || sensors[1].TempCelsius != 41 {
		t.Fatalf("unexpected unlabeled hwmon sensor: %+v", sensors[1])
	}
	if sensors[2].Name != "x86_pkg_temp" || sensors[2].TempCelsius != 43 {
		t.Fatalf("unexpected thermal-zone sensor: %+v", sensors[2])
	}
}

func TestReadSensorsFromSkipsInvalidReadings(t *testing.T) {
	root := t.TempDir()
	hwmon := filepath.Join(root, "hwmon0")
	if err := os.MkdirAll(hwmon, 0o755); err != nil {
		t.Fatal(err)
	}
	for name, contents := range map[string]string{
		"temp1_input": "not-a-temperature\n",
		"temp2_input": "999999\n",
	} {
		if err := os.WriteFile(filepath.Join(hwmon, name), []byte(contents), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	sensors := readSensorsFrom(filepath.Join(root, "hwmon*", "temp*_input"), filepath.Join(root, "missing*"))
	if len(sensors) != 0 {
		t.Fatalf("expected invalid sensors to be skipped, got %+v", sensors)
	}
}

func TestSensorPriorityPrefersCPUAndLeavesStorageLast(t *testing.T) {
	tests := []struct {
		name string
		want int
	}{
		{"k10temp Tctl", 0},
		{"coretemp Package id 0", 0},
		{"asusec CPU", 0},
		{"nouveau temp1", 2},
		{"acpitz temp1", 3},
		{"nvme Composite", 4},
	}
	for _, tt := range tests {
		if got := sensorPriority(tt.name); got != tt.want {
			t.Errorf("sensorPriority(%q) = %d, want %d", tt.name, got, tt.want)
		}
	}
}
