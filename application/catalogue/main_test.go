package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestProducts(t *testing.T) {
	configureCatalogue(t)
	w := httptest.NewRecorder()
	handler().ServeHTTP(w, httptest.NewRequest("GET", "/products", nil))
	var p []Product
	if json.Unmarshal(w.Body.Bytes(), &p) != nil || len(p) != 4 || w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	for _, v := range p {
		if v.Price <= 0 {
			t.Fatal("invalid price")
		}
	}
}
func TestMissing(t *testing.T) {
	configureCatalogue(t)
	w := httptest.NewRecorder()
	handler().ServeHTTP(w, httptest.NewRequest("GET", "/products/missing", nil))
	if w.Code != 404 {
		t.Fatal(w.Code)
	}
}

func configureCatalogue(t *testing.T) {
	t.Helper()
	source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[{"id":"mug","name":"Mug","price":149900,"currency":"INR","emoji":"☕"},{"id":"notebook","name":"Notebook","price":99900,"currency":"INR","emoji":"📓"},{"id":"shirt","name":"Shirt","price":239900,"currency":"INR","emoji":"👕"},{"id":"keyboard","name":"Keyboard","price":649900,"currency":"INR","emoji":"⌨️"}]`))
	}))
	t.Cleanup(source.Close)
	t.Setenv("COMMERCE_URL", source.URL)
}

func TestCommerceCatalogue(t *testing.T) {
	source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/catalogue/products" {
			t.Error(r.URL.Path)
		}
		_, _ = w.Write([]byte(`[{"id":"new-product","name":"New","price":109900,"currency":"INR","emoji":"◈","stock":3}]`))
	}))
	defer source.Close()
	t.Setenv("COMMERCE_URL", source.URL)
	response := httptest.NewRecorder()
	handler().ServeHTTP(response, httptest.NewRequest("GET", "/products/new-product", nil))
	var product Product
	if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &product) != nil || product.ID != "new-product" || product.Stock == nil || *product.Stock != 3 {
		t.Fatal(response.Body.String())
	}
}

func TestCommerceFailureDoesNotServeStalePrices(t *testing.T) {
	source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(503) }))
	defer source.Close()
	t.Setenv("COMMERCE_URL", source.URL)
	response := httptest.NewRecorder()
	handler().ServeHTTP(response, httptest.NewRequest("GET", "/products", nil))
	if response.Code != 503 {
		t.Fatal(response.Code)
	}
}

func TestUnconfiguredCatalogueDoesNotReturnDemoProducts(t *testing.T) {
	t.Setenv("COMMERCE_URL", "")
	for _, path := range []string{"/products", "/health/ready"} {
		response := httptest.NewRecorder()
		handler().ServeHTTP(response, httptest.NewRequest("GET", path, nil))
		if response.Code != 503 {
			t.Fatalf("%s returned %d without an inventory source", path, response.Code)
		}
	}
}

func TestDependencyFailureAffectsReadinessButNotLiveness(t *testing.T) {
	source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(503) }))
	defer source.Close()
	t.Setenv("COMMERCE_URL", source.URL)
	for path, expected := range map[string]int{"/health/live": 200, "/health/ready": 503} {
		response := httptest.NewRecorder()
		handler().ServeHTTP(response, httptest.NewRequest("GET", path, nil))
		if response.Code != expected {
			t.Fatalf("%s returned %d, want %d", path, response.Code, expected)
		}
	}
}
