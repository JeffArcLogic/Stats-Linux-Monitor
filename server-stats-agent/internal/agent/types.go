package agent

import "time"

type Snapshot struct {
	Schema       string        `json:"schema"`
	Host        HostInfo      `json:"host"`
	Timestamp   time.Time     `json:"timestamp"`
	UptimeSec   float64       `json:"uptimeSec"`
	CPU         CPUStats      `json:"cpu"`
	Load        LoadStats     `json:"load"`
	Memory      MemoryStats   `json:"memory"`
	Swap        SwapStats     `json:"swap"`
	Disks       []DiskStats   `json:"disks"`
	Network     []NetStats    `json:"network"`
	Temperature []SensorStats `json:"temperature"`
	GPU         []GPUStats    `json:"gpu,omitempty"`
	Processes   []ProcessInfo `json:"processes"`
}

type HostInfo struct {
	Name     string `json:"name"`
	OS       string `json:"os"`
	Kernel   string `json:"kernel"`
	Platform string `json:"platform"`
}

type CPUStats struct {
	UsagePercent float64   `json:"usagePercent"`
	Cores        int       `json:"cores"`
	PerCore      []float64 `json:"perCore"`
}

type LoadStats struct {
	One     float64 `json:"one"`
	Five    float64 `json:"five"`
	Fifteen float64 `json:"fifteen"`
}

type MemoryStats struct {
	TotalBytes     uint64  `json:"totalBytes"`
	UsedBytes      uint64  `json:"usedBytes"`
	AvailableBytes uint64  `json:"availableBytes"`
	UsagePercent   float64 `json:"usagePercent"`
}

type SwapStats struct {
	TotalBytes   uint64  `json:"totalBytes"`
	UsedBytes    uint64  `json:"usedBytes"`
	UsagePercent float64 `json:"usagePercent"`
}

type DiskStats struct {
	Mountpoint   string  `json:"mountpoint"`
	Device      string  `json:"device"`
	FSType      string  `json:"fsType"`
	TotalBytes  uint64  `json:"totalBytes"`
	UsedBytes   uint64  `json:"usedBytes"`
	FreeBytes   uint64  `json:"freeBytes"`
	UsagePercent float64 `json:"usagePercent"`
}

type NetStats struct {
	Interface     string  `json:"interface"`
	RxBytes       uint64  `json:"rxBytes"`
	TxBytes       uint64  `json:"txBytes"`
	RxBytesPerSec float64 `json:"rxBytesPerSec"`
	TxBytesPerSec float64 `json:"txBytesPerSec"`
}

type SensorStats struct {
	Name        string  `json:"name"`
	TempCelsius float64 `json:"tempCelsius"`
}

type GPUStats struct {
	Name         string  `json:"name"`
	UsagePercent float64 `json:"usagePercent"`
	MemoryUsedMB uint64  `json:"memoryUsedMB"`
	MemoryTotalMB uint64 `json:"memoryTotalMB"`
	TempCelsius  float64 `json:"tempCelsius"`
}

type ProcessInfo struct {
	PID         int     `json:"pid"`
	Name        string  `json:"name"`
	CPUPercent  float64 `json:"cpuPercent"`
	MemoryBytes uint64  `json:"memoryBytes"`
}

type Health struct {
	OK        bool      `json:"ok"`
	Timestamp time.Time `json:"timestamp"`
	Host      string    `json:"host"`
	Version   string    `json:"version"`
}
