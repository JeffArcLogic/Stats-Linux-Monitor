package agent

import (
	"bufio"
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

type CollectorConfig struct {
	Hostname string
	Interval time.Duration
}

type Collector struct {
	config CollectorConfig
	mu     sync.Mutex

	lastCPU      cpuTimes
	lastPerCore  []cpuTimes
	lastNet      map[string]netCounters
	lastSnapshot time.Time
}

func NewCollector(config CollectorConfig) *Collector {
	if config.Interval == 0 {
		config.Interval = 2 * time.Second
	}
	return &Collector{config: config, lastNet: map[string]netCounters{}}
}

func (c *Collector) Snapshot() (Snapshot, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := time.Now()
	host := c.config.Hostname
	if host == "" {
		host, _ = os.Hostname()
	}

	snapshot := Snapshot{
		Schema:      "stats.linux.snapshot.v1",
		Host:        HostInfo{Name: host, OS: readOSName(), Kernel: readKernel(), Platform: runtime.GOARCH},
		Timestamp:   now,
		UptimeSec:   readUptime(),
		Load:        readLoad(),
		Memory:      MemoryStats{},
		Swap:        SwapStats{},
		Disks:       readDisks(),
		Temperature: readSensors(),
		GPU:         readNVIDIA(),
		Processes:   readProcesses(8),
	}

	snapshot.CPU = c.readCPU()
	snapshot.Memory, snapshot.Swap = readMemory()
	snapshot.Network = c.readNetwork(now)
	c.lastSnapshot = now
	return snapshot, nil
}

func (c *Collector) readCPU() CPUStats {
	data, err := os.ReadFile("/proc/stat")
	if err != nil {
		return CPUStats{}
	}
	total, cores, err := parseCPUTimes(string(data))
	if err != nil {
		return CPUStats{}
	}

	var usage float64
	var perCore []float64
	if c.lastCPU.Total != 0 {
		usage = cpuUsagePercent(c.lastCPU, total)
	}
	if len(c.lastPerCore) == len(cores) {
		for i, core := range cores {
			perCore = append(perCore, cpuUsagePercent(c.lastPerCore[i], core))
		}
	}
	c.lastCPU = total
	c.lastPerCore = cores
	return CPUStats{UsagePercent: usage, Cores: len(cores), PerCore: perCore}
}

func readMemory() (MemoryStats, SwapStats) {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return MemoryStats{}, SwapStats{}
	}
	mem, swap, err := parseMeminfo(string(data))
	if err != nil {
		return MemoryStats{}, SwapStats{}
	}
	return mem, swap
}

func readLoad() LoadStats {
	data, err := os.ReadFile("/proc/loadavg")
	if err != nil {
		return LoadStats{}
	}
	load, err := parseLoadavg(string(data))
	if err != nil {
		return LoadStats{}
	}
	return load
}

func readUptime() float64 {
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return 0
	}
	fields := strings.Fields(string(data))
	if len(fields) == 0 {
		return 0
	}
	value, _ := strconv.ParseFloat(fields[0], 64)
	return value
}

func (c *Collector) readNetwork(now time.Time) []NetStats {
	data, err := os.ReadFile("/proc/net/dev")
	if err != nil {
		return nil
	}
	current, err := parseNetDev(string(data))
	if err != nil {
		return nil
	}
	elapsed := now.Sub(c.lastSnapshot).Seconds()
	if elapsed <= 0 {
		elapsed = c.config.Interval.Seconds()
	}
	var out []NetStats
	for iface, counters := range current {
		stat := NetStats{Interface: iface, RxBytes: counters.Rx, TxBytes: counters.Tx}
		if prev, ok := c.lastNet[iface]; ok {
			if counters.Rx >= prev.Rx {
				stat.RxBytesPerSec = float64(counters.Rx-prev.Rx) / elapsed
			}
			if counters.Tx >= prev.Tx {
				stat.TxBytesPerSec = float64(counters.Tx-prev.Tx) / elapsed
			}
		}
		out = append(out, stat)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Interface < out[j].Interface })
	c.lastNet = current
	return out
}

func readDisks() []DiskStats {
	data, err := os.ReadFile("/proc/mounts")
	if err != nil {
		return nil
	}
	skip := map[string]bool{
		"autofs": true, "binfmt_misc": true, "bpf": true, "cgroup": true,
		"cgroup2": true, "configfs": true, "debugfs": true, "devpts": true,
		"devtmpfs": true, "efivarfs": true, "fusectl": true, "hugetlbfs": true,
		"mqueue": true, "overlay": true, "proc": true, "pstore": true,
		"securityfs": true, "sysfs": true, "tmpfs": true, "tracefs": true,
	}
	var out []DiskStats
	scanner := bufio.NewScanner(strings.NewReader(string(data)))
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 3 || skip[fields[2]] {
			continue
		}
		mount := strings.ReplaceAll(fields[1], `\040`, " ")
		var fs syscall.Statfs_t
		if err := syscall.Statfs(mount, &fs); err != nil {
			continue
		}
		total := uint64(fs.Blocks) * uint64(fs.Bsize)
		free := uint64(fs.Bavail) * uint64(fs.Bsize)
		if total == 0 {
			continue
		}
		used := total - free
		out = append(out, DiskStats{
			Mountpoint: mount, Device: fields[0], FSType: fields[2],
			TotalBytes: total, UsedBytes: used, FreeBytes: free, UsagePercent: percent(used, total),
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Mountpoint < out[j].Mountpoint })
	return out
}

func readSensors() []SensorStats {
	var out []SensorStats
	paths, _ := filepath.Glob("/sys/class/thermal/thermal_zone*/temp")
	for _, path := range paths {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		raw, err := strconv.ParseFloat(strings.TrimSpace(string(data)), 64)
		if err != nil {
			continue
		}
		name := filepath.Base(filepath.Dir(path))
		if typeData, err := os.ReadFile(filepath.Join(filepath.Dir(path), "type")); err == nil {
			name = strings.TrimSpace(string(typeData))
		}
		out = append(out, SensorStats{Name: name, TempCelsius: raw / 1000})
	}
	return out
}

func readNVIDIA() []GPUStats {
	path, err := exec.LookPath("nvidia-smi")
	if err != nil {
		return nil
	}
	cmd := exec.Command(path, "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu", "--format=csv,noheader,nounits")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	data, err := cmd.Output()
	if err != nil {
		return nil
	}
	var out []GPUStats
	for _, line := range strings.Split(strings.TrimSpace(string(data)), "\n") {
		parts := strings.Split(line, ",")
		if len(parts) < 5 {
			continue
		}
		usage, _ := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
		used, _ := strconv.ParseUint(strings.TrimSpace(parts[2]), 10, 64)
		total, _ := strconv.ParseUint(strings.TrimSpace(parts[3]), 10, 64)
		temp, _ := strconv.ParseFloat(strings.TrimSpace(parts[4]), 64)
		out = append(out, GPUStats{
			Name: strings.TrimSpace(parts[0]), UsagePercent: usage,
			MemoryUsedMB: used, MemoryTotalMB: total, TempCelsius: temp,
		})
	}
	return out
}

func readProcesses(limit int) []ProcessInfo {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return nil
	}
	var out []ProcessInfo
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		pid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		nameData, err := os.ReadFile(filepath.Join("/proc", entry.Name(), "comm"))
		if err != nil {
			continue
		}
		status, _ := os.ReadFile(filepath.Join("/proc", entry.Name(), "status"))
		out = append(out, ProcessInfo{PID: pid, Name: strings.TrimSpace(string(nameData)), MemoryBytes: parseRSS(status)})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].MemoryBytes > out[j].MemoryBytes })
	if len(out) > limit {
		out = out[:limit]
	}
	return out
}

func parseRSS(status []byte) uint64 {
	for _, line := range strings.Split(string(status), "\n") {
		if strings.HasPrefix(line, "VmRSS:") {
			fields := strings.Fields(line)
			if len(fields) >= 2 {
				value, _ := strconv.ParseUint(fields[1], 10, 64)
				return value * 1024
			}
		}
	}
	return 0
}

func readOSName() string {
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return runtime.GOOS
	}
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "PRETTY_NAME=") {
			return strings.Trim(strings.TrimPrefix(line, "PRETTY_NAME="), `"`)
		}
	}
	return runtime.GOOS
}

func readKernel() string {
	var uts syscall.Utsname
	if err := syscall.Uname(&uts); err != nil {
		return ""
	}
	return charsToString(uts.Release[:])
}

func charsToString(chars []int8) string {
	var b []byte
	for _, c := range chars {
		if c == 0 {
			break
		}
		b = append(b, byte(c))
	}
	return string(b)
}
