package agent

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestAuthRequired(t *testing.T) {
	server := NewServer(NewCollector(CollectorConfig{Hostname: "test"}), "secret")
	req := httptest.NewRequest(http.MethodGet, "/v1/health", nil)
	rec := httptest.NewRecorder()
	server.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestHealthAuthorized(t *testing.T) {
	server := NewServer(NewCollector(CollectorConfig{Hostname: "test"}), "secret")
	req := httptest.NewRequest(http.MethodGet, "/v1/health", nil)
	req.Header.Set("Authorization", "Bearer secret")
	rec := httptest.NewRecorder()
	server.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), `"ok":true`) {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}

func TestStreamEmitsSSEFrame(t *testing.T) {
	server := NewServer(NewCollector(CollectorConfig{Hostname: "test", Interval: 10 * time.Millisecond}), "secret")
	req := httptest.NewRequest(http.MethodGet, "/v1/stream", nil)
	req.Header.Set("Authorization", "Bearer secret")
	ctx, cancel := context.WithCancel(req.Context())
	req = req.WithContext(ctx)
	rec := httptest.NewRecorder()

	done := make(chan struct{})
	go func() {
		server.Routes().ServeHTTP(rec, req)
		close(done)
	}()
	time.Sleep(25 * time.Millisecond)
	cancel()
	<-done

	if !strings.Contains(rec.Body.String(), "event: snapshot") {
		t.Fatalf("expected snapshot frame, got %q", rec.Body.String())
	}
}
