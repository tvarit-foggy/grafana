package middleware

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/grafana/grafana/pkg/bus"
	"github.com/grafana/grafana/pkg/models"
	"github.com/grafana/grafana/pkg/services/contexthandler"
	"github.com/grafana/grafana/pkg/setting"
	"github.com/grafana/grafana/pkg/web"
)

func ViewRedirect(cfg *setting.Cfg) web.Handler {
	return func(res http.ResponseWriter, req *http.Request, c *web.Context) {
		view := req.URL.Query().Get("view")

		if view == "" {
			return
		}

		ctx := contexthandler.FromContext(req.Context())
		if !ctx.IsSignedIn {
			return
		}

		if view == ctx.View {
			return
		}

		cmd := models.SetViewCommand{UserId: ctx.UserId, OrgId: ctx.OrgId, View: view}
		if err := bus.Dispatch(ctx.Req.Context(), &cmd); err != nil {
			if ctx.IsApiRequest() {
				ctx.JsonApiErr(404, "Failed to change active view", nil)
			} else {
				http.Error(ctx.Resp, "Failed to change active view", http.StatusNotFound)
			}
		}

		newURL := fmt.Sprintf("%s%s?%s", cfg.AppURL, strings.TrimPrefix(c.Req.URL.Path, "/"), c.Req.URL.Query().Encode())
		c.Redirect(newURL, 302)
	}
}
