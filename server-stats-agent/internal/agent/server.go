package agent

import (
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

const Version = "0.1.0"

type Server struct {
	collector *Collector
	token     string
}

func NewServer(collector *Collector, token string) *Server {
	return &Server{collector: collector, token: token}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/health", s.auth(s.health))
	mux.HandleFunc("/v1/snapshot", s.auth(s.snapshot))
	mux.HandleFunc("/v1/stream", s.auth(s.stream))
	return mux
}

func (s *Server) auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		got := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if s.token == "" || !strings.HasPrefix(r.Header.Get("Authorization"), "Bearer ") || subtle.ConstantTimeCompare([]byte(got), []byte(s.token)) != 1 {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	hostname := s.collector.config.Hostname
	writeJSON(w, Health{OK: true, Timestamp: time.Now(), Host: hostname, Version: Version})
}

func (s *Server) snapshot(w http.ResponseWriter, _ *http.Request) {
	snapshot, err := s.collector.Snapshot()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, snapshot)
}

func (s *Server) stream(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "stream unsupported", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	interval := s.collector.config.Interval
	if interval == 0 {
		interval = 2 * time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		snapshot, err := s.collector.Snapshot()
		if err == nil {
			data, _ := json.Marshal(snapshot)
			_, _ = w.Write([]byte("event: snapshot\n"))
			_, _ = w.Write([]byte("data: "))
			_, _ = w.Write(data)
			_, _ = w.Write([]byte("\n\n"))
			flusher.Flush()
		}

		select {
		case <-r.Context().Done():
			return
		case <-ticker.C:
		}
	}
}

func writeJSON(w http.ResponseWriter, value any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(value)
}
