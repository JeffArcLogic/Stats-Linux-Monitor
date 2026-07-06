//
//  RAM.swift
//  Tests
//
//  Created by Serhiy Mytrovtsiy on 16/04/2022.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2022 Serhiy Mytrovtsiy. All rights reserved.
//

import XCTest
import RAM
import Remote

class RAM: XCTestCase {
    func testProcessReader_parseProcess() throws {
        var process = ProcessReader.parseProcess("3127  lldb-rpc-server  611M")
        XCTAssertEqual(process.pid, 3127)
        XCTAssertEqual(process.name, "lldb-rpc-server")
        XCTAssertEqual(process.usage, 611 * Double(1000 * 1000))

        process = ProcessReader.parseProcess("257   WindowServer     210M")
        XCTAssertEqual(process.pid, 257)
        XCTAssertEqual(process.name, "WindowServer")
        XCTAssertEqual(process.usage, 210 * Double(1000 * 1000))

        process = ProcessReader.parseProcess("7752  phpstorm         1819M")
        XCTAssertEqual(process.pid, 7752)
        XCTAssertEqual(process.name, "phpstorm")
        XCTAssertEqual(process.usage, 1819.0 / 1024 * 1000 * Double(1000 * 1000))

        process = ProcessReader.parseProcess("359   NotificationCent 62M")
        XCTAssertEqual(process.pid, 359)
        XCTAssertEqual(process.name, "NotificationCent")
        XCTAssertEqual(process.usage, 62 * Double(1000 * 1000))

        process = ProcessReader.parseProcess("623    SafariCloudHisto 1608K")
        XCTAssertEqual(process.pid, 623)
        XCTAssertEqual(process.name, "SafariCloudHisto")
        XCTAssertEqual(process.usage, (1608/1024) * Double(1000 * 1000))

        process = ProcessReader.parseProcess("174    WindowServer     1442M+ ")
        XCTAssertEqual(process.pid, 174)
        XCTAssertEqual(process.name, "WindowServer")
        XCTAssertEqual(process.usage, 1442 * Double(1000 * 1000))

        process = ProcessReader.parseProcess("329    Finder           488M+ ")
        XCTAssertEqual(process.pid, 329)
        XCTAssertEqual(process.name, "Finder")
        XCTAssertEqual(process.usage, 488 * Double(1000 * 1000))

        process = ProcessReader.parseProcess("7163* AutoCAD LT 2023  11G  ")
        XCTAssertEqual(process.pid, 7163)
        XCTAssertEqual(process.name, "AutoCAD LT 2023")
        XCTAssertEqual(process.usage, 11 * Double(1024 * 1000 * 1000))
    }

    func testKernelTask() throws {
        var process = ProcessReader.parseProcess("0      kernel_task      270M ")
        XCTAssertEqual(process.pid, 0)
        XCTAssertEqual(process.name, "kernel_task")
        XCTAssertEqual(process.usage, 270 * Double(1000 * 1000))

        process = ProcessReader.parseProcess("0     kernel_task      280M")
        XCTAssertEqual(process.pid, 0)
        XCTAssertEqual(process.name, "kernel_task")
        XCTAssertEqual(process.usage, 280 * Double(1000 * 1000))
    }

    func testSizes() throws {
        var process = ProcessReader.parseProcess("0  com.apple.Virtua 8463M")
        XCTAssertEqual(process.pid, 0)
        XCTAssertEqual(process.name, "com.apple.Virtua")
        XCTAssertEqual(process.usage, 8463.0 / 1024 * 1000 * 1000 * 1000)

        process = ProcessReader.parseProcess("0  Safari           658M")
        XCTAssertEqual(process.pid, 0)
        XCTAssertEqual(process.name, "Safari")
        XCTAssertEqual(process.usage, 658 * Double(1000 * 1000))
    }
}

class LinuxServers: XCTestCase {
    func testSnapshotDecoding() throws {
        let json = """
        {
          "schema": "stats.linux.snapshot.v1",
          "host": {"name": "nas", "os": "Ubuntu 24.04", "kernel": "6.8.0", "platform": "amd64"},
          "timestamp": "2026-07-05T20:00:00Z",
          "uptimeSec": 120.5,
          "cpu": {"usagePercent": 32.5, "cores": 8, "perCore": [30, 35]},
          "load": {"one": 1.2, "five": 1.0, "fifteen": 0.7},
          "memory": {"totalBytes": 1000, "usedBytes": 610, "availableBytes": 390, "usagePercent": 61},
          "swap": {"totalBytes": 100, "usedBytes": 10, "usagePercent": 10},
          "disks": [{"mountpoint": "/", "device": "/dev/sda1", "fsType": "ext4", "totalBytes": 1000, "usedBytes": 770, "freeBytes": 230, "usagePercent": 77}],
          "network": [{"interface": "eth0", "rxBytes": 1000, "txBytes": 2000, "rxBytesPerSec": 10, "txBytesPerSec": 20}],
          "temperature": [{"name": "cpu", "tempCelsius": 42.5}],
          "gpu": [{"name": "RTX", "usagePercent": 5, "memoryUsedMB": 100, "memoryTotalMB": 1000, "tempCelsius": 45}],
          "processes": [{"pid": 1, "name": "systemd", "cpuPercent": 0, "memoryBytes": 1234}]
        }
        """
        let snapshot = try LinuxServerClient.decoder.decode(LinuxServerSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.host.name, "nas")
        XCTAssertEqual(snapshot.diskUsagePercent, 77)
        XCTAssertEqual(snapshot.networkBytesPerSecond, 30)
    }

    func testSnapshotDecodingAllowsNullTemperature() throws {
        let json = """
        {
          "schema": "stats.linux.snapshot.v1",
          "host": {"name": "nas", "os": "Ubuntu 24.04", "kernel": "6.8.0", "platform": "amd64"},
          "timestamp": "2026-07-05T20:00:00Z",
          "uptimeSec": 120.5,
          "cpu": {"usagePercent": 32.5, "cores": 8, "perCore": [30, 35]},
          "load": {"one": 1.2, "five": 1.0, "fifteen": 0.7},
          "memory": {"totalBytes": 1000, "usedBytes": 610, "availableBytes": 390, "usagePercent": 61},
          "swap": {"totalBytes": 100, "usedBytes": 10, "usagePercent": 10},
          "disks": [],
          "network": [],
          "temperature": null,
          "processes": []
        }
        """
        let snapshot = try LinuxServerClient.decoder.decode(LinuxServerSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.temperature.count, 0)
    }

    func testDiskUsagePrefersRootMount() throws {
        let json = """
        {
          "schema": "stats.linux.snapshot.v1",
          "host": {"name": "itx", "os": "Ubuntu 26.04 LTS", "kernel": "7.0.0", "platform": "amd64"},
          "timestamp": "2026-07-05T20:00:00Z",
          "uptimeSec": 120.5,
          "cpu": {"usagePercent": 32.5, "cores": 8, "perCore": [30, 35]},
          "load": {"one": 1.2, "five": 1.0, "fifteen": 0.7},
          "memory": {"totalBytes": 1000, "usedBytes": 610, "availableBytes": 390, "usagePercent": 61},
          "swap": {"totalBytes": 100, "usedBytes": 10, "usagePercent": 10},
          "disks": [
            {"mountpoint": "/boot", "device": "/dev/nvme0n1p2", "fsType": "ext4", "totalBytes": 1000, "usedBytes": 950, "freeBytes": 50, "usagePercent": 95},
            {"mountpoint": "/", "device": "/dev/mapper/ubuntu--vg-ubuntu--lv", "fsType": "ext4", "totalBytes": 100000, "usedBytes": 57000, "freeBytes": 43000, "usagePercent": 57}
          ],
          "network": [],
          "temperature": [],
          "processes": []
        }
        """
        let snapshot = try LinuxServerClient.decoder.decode(LinuxServerSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.primaryDisk?.mountpoint, "/")
        XCTAssertEqual(snapshot.diskUsagePercent, 57)
    }

    func testConfigNormalizesHostWithoutScheme() throws {
        let config = LinuxServerConfig(id: "test", name: "NAS", url: "nas.tailnet.ts.net:9783")
        XCTAssertEqual(config.endpoint?.scheme, "http")
        XCTAssertEqual(config.endpoint?.host, "nas.tailnet.ts.net")
        XCTAssertEqual(config.endpoint?.port, 9783)
    }
}
