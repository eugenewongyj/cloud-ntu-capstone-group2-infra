package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/grafana/grafana-plugin-sdk-go/backend"
)

const (
	pluginID = "capstone-srecontrol-app"

	controllerURL = "http://capstone-assessment-controller.monitoring.svc.cluster.local:8080"

	maxRequestBytes  = 4096
	maxResponseBytes = 2 * 1024 * 1024
)

type App struct {
	client  *http.Client
	baseURL string
	token   string
}

func newApp(token string) (*App, error) {
	if len(token) < 32 {
		return nil, errors.New(
			"controller credential is missing or invalid",
		)
	}

	return &App{
		baseURL: controllerURL,
		token:   token,
		client: &http.Client{
			Timeout: 15 * time.Second,
			CheckRedirect: func(
				req *http.Request,
				via []*http.Request,
			) error {
				return http.ErrUseLastResponse
			},
			Transport: &http.Transport{
				MaxIdleConns:        10,
				MaxIdleConnsPerHost: 5,
				IdleConnTimeout:     30 * time.Second,
			},
		},
	}, nil
}

func sendJSON(
	sender backend.CallResourceResponseSender,
	status int,
	message string,
) error {
	body, _ := json.Marshal(map[string]string{
		"error": message,
	})

	return sender.Send(&backend.CallResourceResponse{
		Status: status,
		Headers: map[string][]string{
			"Content-Type":           {"application/json"},
			"Cache-Control":          {"no-store"},
			"X-Content-Type-Options": {"nosniff"},
		},
		Body: body,
	})
}

func (a *App) CallResource(
	ctx context.Context,
	req *backend.CallResourceRequest,
	sender backend.CallResourceResponseSender,
) error {

	if req == nil {
		return sendJSON(sender, 400, "Invalid request")
	}

	pc := req.PluginContext

	if pc.User == nil || pc.OrgID != 1 {
		return sendJSON(sender, 403, "Access denied")
	}

	role := pc.User.Role

	if role != "Viewer" &&
		role != "Editor" &&
		role != "Admin" {
		return sendJSON(sender, 403, "Access denied")
	}

	path := "/" + strings.TrimPrefix(req.Path, "/")

	switch req.Method + " " + path {

	case "GET /api/v1/status",
		"GET /api/v1/history":

		if len(req.Body) != 0 {
			return sendJSON(
				sender, 400, "Unexpected request body",
			)
		}

	case "POST /api/v1/start",
		"POST /api/v1/stop":

		if role != "Admin" && role != "Editor" {
			return sendJSON(
				sender, 403, "Operator access required",
			)
		}

		if len(req.Body) > maxRequestBytes {
			return sendJSON(
				sender, 413, "Request body too large",
			)
		}

		if !json.Valid(req.Body) {
			return sendJSON(
				sender, 400, "Invalid JSON request",
			)
		}

	default:
		return sendJSON(
			sender, 404, "Unsupported operation",
		)
	}

	upstream, err := http.NewRequestWithContext(
		ctx,
		req.Method,
		a.baseURL+path,
		bytes.NewReader(req.Body),
	)

	if err != nil {
		return sendJSON(
			sender, 500, "Request initialization failed",
		)
	}

	upstream.Header.Set(
		"Authorization", "Bearer "+a.token,
	)

	upstream.Header.Set(
		"Content-Type", "application/json",
	)

	upstream.Header.Set(
		"Accept", "application/json",
	)

	response, err := a.client.Do(upstream)

	if err != nil {
		return sendJSON(
			sender, 502, "Assessment controller unavailable",
		)
	}

	defer response.Body.Close()

	if response.StatusCode >= 300 &&
		response.StatusCode < 400 {
		return sendJSON(
			sender, 502, "Unexpected controller redirect",
		)
	}

	body, err := io.ReadAll(
		io.LimitReader(
			response.Body,
			maxResponseBytes+1,
		),
	)

	if err != nil || len(body) > maxResponseBytes {
		return sendJSON(
			sender, 502, "Invalid controller response",
		)
	}

	if !json.Valid(body) {
		return sendJSON(
			sender, 502, "Invalid controller response format",
		)
	}

	if response.StatusCode >= 500 {
		return sendJSON(
			sender, 502, "Assessment controller error",
		)
	}

	return sender.Send(&backend.CallResourceResponse{
		Status: response.StatusCode,
		Headers: map[string][]string{
			"Content-Type":           {"application/json"},
			"Cache-Control":          {"no-store"},
			"X-Content-Type-Options": {"nosniff"},
		},
		Body: body,
	})
}

func (a *App) Dispose() {
	a.client.CloseIdleConnections()
}

var _ backend.CallResourceHandler = (*App)(nil)
