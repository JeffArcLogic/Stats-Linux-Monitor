package agent

import (
	"bufio"
	"errors"
	"strconv"
	"strings"
)

type cpuTimes struct {
	Idle  uint64
	Total uint64
}

type netCounters struct {
	Rx uint64
	Tx uint64
}

func parseCPUTimes(procStat string) (cpuTimes, []cpuTimes, error) {
	var total cpuTimes
	var cores []cpuTimes
	scanner := bufio.NewScanner(strings.NewReader(procStat))
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 5 || !strings.HasPrefix(fields[0], "cpu") {
			continue
		}

		var values []uint64
		for _, field := range fields[1:] {
			v, err := strconv.ParseUint(field, 10, 64)
			if err != nil {
				return cpuTimes{}, nil, err
			}
			values = append(values, v)
		}

		idle := values[3]
		if len(values) > 4 {
			idle += values[4]
		}
		var sum uint64
		for _, v := range values {
			sum += v
		}
		t := cpuTimes{Idle: idle, Total: sum}
		if fields[0] == "cpu" {
			total = t
		} else {
			cores = append(cores, t)
		}
	}
	if total.Total == 0 {
		return cpuTimes{}, nil, errors.New("missing aggregate cpu line")
	}
	return total, cores, scanner.Err()
}

func cpuUsagePercent(prev, curr cpuTimes) float64 {
	totalDelta := curr.Total - prev.Total
	idleDelta := curr.Idle - prev.Idle
	if totalDelta == 0 || idleDelta > totalDelta {
		return 0
	}
	return float64(totalDelta-idleDelta) / float64(totalDelta) * 100
}

func parseMeminfo(meminfo string) (MemoryStats, SwapStats, error) {
	values := map[string]uint64{}
	scanner := bufio.NewScanner(strings.NewReader(meminfo))
	for scanner.Scan() {
		fields := strings.Fields(strings.TrimSuffix(scanner.Text(), ":"))
		if len(fields) < 2 {
			continue
		}
		key := strings.TrimSuffix(fields[0], ":")
		value, err := strconv.ParseUint(fields[1], 10, 64)
		if err != nil {
			return MemoryStats{}, SwapStats{}, err
		}
		values[key] = value * 1024
	}
	if err := scanner.Err(); err != nil {
		return MemoryStats{}, SwapStats{}, err
	}
	total := values["MemTotal"]
	available := values["MemAvailable"]
	if available == 0 {
		available = values["MemFree"] + values["Buffers"] + values["Cached"]
	}
	used := total - available
	mem := MemoryStats{
		TotalBytes:     total,
		UsedBytes:      used,
		AvailableBytes: available,
		UsagePercent:   percent(used, total),
	}

	swapTotal := values["SwapTotal"]
	swapFree := values["SwapFree"]
	swapUsed := swapTotal - swapFree
	swap := SwapStats{
		TotalBytes:   swapTotal,
		UsedBytes:    swapUsed,
		UsagePercent: percent(swapUsed, swapTotal),
	}
	return mem, swap, nil
}

func parseLoadavg(loadavg string) (LoadStats, error) {
	fields := strings.Fields(loadavg)
	if len(fields) < 3 {
		return LoadStats{}, errors.New("invalid loadavg")
	}
	one, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return LoadStats{}, err
	}
	five, err := strconv.ParseFloat(fields[1], 64)
	if err != nil {
		return LoadStats{}, err
	}
	fifteen, err := strconv.ParseFloat(fields[2], 64)
	if err != nil {
		return LoadStats{}, err
	}
	return LoadStats{One: one, Five: five, Fifteen: fifteen}, nil
}

func parseNetDev(netdev string) (map[string]netCounters, error) {
	out := map[string]netCounters{}
	scanner := bufio.NewScanner(strings.NewReader(netdev))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !strings.Contains(line, ":") {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		iface := strings.TrimSpace(parts[0])
		fields := strings.Fields(parts[1])
		if len(fields) < 16 || iface == "lo" {
			continue
		}
		rx, err := strconv.ParseUint(fields[0], 10, 64)
		if err != nil {
			return nil, err
		}
		tx, err := strconv.ParseUint(fields[8], 10, 64)
		if err != nil {
			return nil, err
		}
		out[iface] = netCounters{Rx: rx, Tx: tx}
	}
	return out, scanner.Err()
}

func percent(used, total uint64) float64 {
	if total == 0 {
		return 0
	}
	return float64(used) / float64(total) * 100
}
