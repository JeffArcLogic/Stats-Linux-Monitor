package main

import (
	"log"
	"net/http"
	"os"
	"time"

	agent "github.com/exelban/stats/server-stats-agent/internal/agent"
)

func main() {
	token := os.Getenv("SERVER_STATS_TOKEN")
	if token == "" {
		log.Fatal("SERVER_STATS_TOKEN is required")
	}

	listen := os.Getenv("SERVER_STATS_LISTEN")
	if listen == "" {
		listen = ":9783"
	}

	hostname, _ := os.Hostname()
	collector := agent.NewCollector(agent.CollectorConfig{
		Hostname: hostname,
		Interval: 2 * time.Second,
	})

	server := agent.NewServer(collector, token)
	log.Printf("server-stats-agent listening on %s", listen)
	log.Fatal(http.ListenAndServe(listen, server.Routes()))
}
