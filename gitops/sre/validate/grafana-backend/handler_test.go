package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/grafana/grafana-plugin-sdk-go/backend"
)

type testSender struct {
	response *backend.CallResourceResponse
}

func (s *testSender) Send(
	response *backend.CallResourceResponse,
) error {
	s.response = response
	return nil
}

func TestAuthorizationAndRouting(t *testing.T) {
	tests := []struct {
		name   string
		role   string
		org    int64
		method string
		path   string
		body   string
		want   int
	}{
		{"Viewer status", "Viewer", 1,
			"GET", "api/v1/status", "", 200},

		{"Viewer history", "Viewer", 1,
			"GET", "api/v1/history", "", 200},

		{"Viewer cannot start", "Viewer", 1,
			"POST", "api/v1/start", `{}`, 403},

		{"Viewer cannot stop", "Viewer", 1,
			"POST", "api/v1/stop", `{}`, 403},

		{"Editor can start", "Editor", 1,
			"POST", "api/v1/start", `{}`, 200},

		{"Admin can stop", "Admin", 1,
			"POST", "api/v1/stop", `{}`, 200},

		{"Unknown role", "Unknown", 1,
			"GET", "api/v1/status", "", 403},

		{"Missing identity", "", 1,
			"GET", "api/v1/status", "", 403},

		{"Wrong organization", "Admin", 2,
			"GET", "api/v1/status", "", 403},

		{"Unknown endpoint", "Admin", 1,
			"GET", "healthz", "", 404},

		{"Unsupported method", "Admin", 1,
			"DELETE", "api/v1/status", "", 404},

		{"Path traversal", "Admin", 1,
			"GET", "api/v1/../status", "", 404},

		{"Invalid JSON", "Admin", 1,
			"POST", "api/v1/start", "invalid", 400},

		{"Oversized body", "Admin", 1,
			"POST", "api/v1/start",
			strings.Repeat("x", 4097), 413},

		{"Unexpected GET body", "Admin", 1,
			"GET", "api/v1/status", `{}`, 400},
	}

	token := strings.Repeat("a", 32)

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var calls atomic.Int32

			server := httptest.NewServer(
				http.HandlerFunc(func(
					w http.ResponseWriter,
					r *http.Request,
				) {
					calls.Add(1)

					if r.Header.Get("Authorization") !=
						"Bearer "+token {
						t.Error("Invalid upstream credential")
					}

					if r.Method != tc.method {
						t.Error("Unexpected upstream method")
					}

					if r.URL.Path != "/"+tc.path {
						t.Error("Unexpected upstream path")
					}

					w.Header().Set(
						"Content-Type",
						"application/json",
					)

					w.Write([]byte(`{"state":"idle"}`))
				}),
			)

			defer server.Close()

			a, err := newApp(token)
			if err != nil {
				t.Fatal(err)
			}

			defer a.Dispose()

			a.baseURL = server.URL

			var user *backend.User

			if tc.role != "" {
				user = &backend.User{
					Role: tc.role,
				}
			}

			req := &backend.CallResourceRequest{
				PluginContext: backend.PluginContext{
					OrgID: tc.org,
					User:  user,
				},
				Method: tc.method,
				Path:   tc.path,
				Body:   []byte(tc.body),
				Headers: map[string][]string{
					"Authorization": {"Bearer forged"},
				},
			}

			sender := &testSender{}

			err = a.CallResource(
				context.Background(),
				req,
				sender,
			)

			if err != nil {
				t.Fatal(err)
			}

			if sender.response == nil {
				t.Fatal("Missing response")
			}

			if sender.response.Status != tc.want {
				t.Fatalf(
					"Expected %d, received %d",
					tc.want,
					sender.response.Status,
				)
			}

			if tc.want == 200 && calls.Load() != 1 {
				t.Fatal("Authorized request not forwarded")
			}

			if tc.want != 200 && calls.Load() != 0 {
				t.Fatal("Rejected request reached controller")
			}
		})
	}
}

func TestMissingCredential(t *testing.T) {
	for _, token := range []string{"", "short"} {
		if _, err := newApp(token); err == nil {
			t.Fatal("Invalid credential accepted")
		}
	}
}
