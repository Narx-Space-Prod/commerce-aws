package main

import (
	"fmt"
	"net/http"
	"sort"
	"strings"
	"sync"
)

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) { w.status = code; w.ResponseWriter.WriteHeader(code) }

type sample struct {
	method, path, status string
	count                int
	sum                  float64
	buckets              []int
}

var bounds = []float64{.01, .05, .1, .25, .5, 1, 2.5, 5, 10}
var mu sync.Mutex
var samples = map[string]*sample{}

func observe(r *http.Request, status int, seconds float64) {
	if strings.HasPrefix(r.URL.Path, "/health/") || r.URL.Path == "/metrics" {
		return
	}
	path := "unmatched"
	if r.URL.Path == "/products" {
		path = "/products"
	} else if strings.HasPrefix(r.URL.Path, "/products/") {
		path = "/products/:id"
	}
	method := r.Method
	if method != "GET" && method != "HEAD" {
		method = "OTHER"
	}
	code := fmt.Sprint(status)
	key := method + path + code
	mu.Lock()
	defer mu.Unlock()
	s := samples[key]
	if s == nil {
		s = &sample{method: method, path: path, status: code, buckets: make([]int, len(bounds))}
		samples[key] = s
	}
	s.count++
	s.sum += seconds
	for i, b := range bounds {
		if seconds <= b {
			s.buckets[i]++
		}
	}
}
func exposition() string {
	mu.Lock()
	defer mu.Unlock()
	var out strings.Builder
	out.WriteString("# TYPE boutique_catalogue_up gauge\nboutique_catalogue_up 1\n# TYPE boutique_http_requests_total counter\n# TYPE boutique_http_request_duration_seconds histogram\n")
	keys := make([]string, 0, len(samples))
	for k := range samples {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		s := samples[k]
		labels := fmt.Sprintf("service=\"catalogue\",method=\"%s\",route=\"%s\",status=\"%s\"", s.method, s.path, s.status)
		fmt.Fprintf(&out, "boutique_http_requests_total{%s} %d\n", labels, s.count)
		for i, b := range bounds {
			fmt.Fprintf(&out, "boutique_http_request_duration_seconds_bucket{%s,le=\"%g\"} %d\n", labels, b, s.buckets[i])
		}
		fmt.Fprintf(&out, "boutique_http_request_duration_seconds_bucket{%s,le=\"+Inf\"} %d\nboutique_http_request_duration_seconds_count{%s} %d\nboutique_http_request_duration_seconds_sum{%s} %g\n", labels, s.count, labels, s.count, labels, s.sum)
	}
	return out.String()
}
