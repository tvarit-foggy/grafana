package channels

import (
	"context"
	"net/url"
	"path"
	"regexp"

	"github.com/prometheus/alertmanager/template"
	"github.com/prometheus/alertmanager/types"

	"github.com/grafana/grafana/pkg/bus"
	"github.com/grafana/grafana/pkg/infra/log"
	"github.com/grafana/grafana/pkg/models"
	"github.com/grafana/grafana/pkg/util"
	deepcopier "github.com/ulule/deepcopier"
)

// EmailNotifier is responsible for sending
// alert notifications over email.
type EmailNotifier struct {
	*Base
	Addresses   []string
	SingleEmail bool
	Message     string
	log         log.Logger
	tmpl        *template.Template
}

// NewEmailNotifier is the constructor function
// for the EmailNotifier.
func NewEmailNotifier(model *NotificationChannelConfig, t *template.Template) (*EmailNotifier, error) {
	if model.Settings == nil {
		return nil, receiverInitError{Cfg: *model, Reason: "no settings supplied"}
	}

	addressesString := model.Settings.Get("addresses").MustString()
	singleEmail := model.Settings.Get("singleEmail").MustBool(false)

	if addressesString == "" {
		return nil, receiverInitError{Reason: "could not find addresses in settings", Cfg: *model}
	}

	// split addresses with a few different ways
	addresses := util.SplitEmails(addressesString)

	return &EmailNotifier{
		Base: NewBase(&models.AlertNotification{
			Uid:                   model.UID,
			Name:                  model.Name,
			Type:                  model.Type,
			DisableResolveMessage: model.DisableResolveMessage,
			Settings:              model.Settings,
		}),
		Addresses:   addresses,
		SingleEmail: singleEmail,
		Message:     model.Settings.Get("message").MustString(),
		log:         log.New("alerting.notifier.email"),
		tmpl:        t,
	}, nil
}

// Notify sends the alert notification.
func (en *EmailNotifier) Notify(ctx context.Context, as ...*types.Alert) (bool, error) {
	var tmplErr error
	tmpl, data := TmplText(ctx, en.tmpl, as, en.log, &tmplErr)

	title := tmpl(DefaultMessageTitleEmbed)

	alertPageURL := en.tmpl.ExternalURL.String()
	ruleURL := en.tmpl.ExternalURL.String()
	u, err := url.Parse(en.tmpl.ExternalURL.String())
	if err == nil {
		basePath := u.Path
		u.Path = path.Join(basePath, "/alerting/list")
		ruleURL = u.String()
		u.RawQuery = "alertState=firing&view=state"
		alertPageURL = u.String()
	} else {
		en.log.Debug("failed to parse external URL", "url", en.tmpl.ExternalURL.String(), "err", err.Error())
	}

	checkUrl := func(input string) bool {
		pattern := `^(https?|ftp)://[^\s/$.?#].[^\s]*$`
		regex := regexp.MustCompile(pattern)
		return regex.MatchString(input)
	}
	for i := range data.Alerts {
		alert := &data.Alerts[i]
		if alert.URLAnnotations == nil {
			alert.URLAnnotations = map[string]string{}
		}
		if alert.URLLabels == nil {
			alert.URLLabels = map[string]string{}
		}
		for key, value := range alert.Labels {
			if checkUrl(value) {
				alert.URLLabels[key] = value
				delete(alert.Labels, key)
			}
		}
		for key, value := range alert.Annotations {
			if checkUrl(value) {
				alert.URLAnnotations[key] = value
				delete(alert.Annotations, key)
			}
		}
	}
	Dispatcher := func(data ExtendedData, isNoDataAlert bool) (bool, error) {
		cmd := &models.SendEmailCommandSync{
			SendEmailCommand: models.SendEmailCommand{
				Subject: title,
				Data: map[string]interface{}{
					"Title":             title,
					"Message":           tmpl(en.Message),
					"Status":            data.Status,
					"Alerts":            data.Alerts,
					"GroupLabels":       data.GroupLabels,
					"CommonLabels":      data.CommonLabels,
					"CommonAnnotations": data.CommonAnnotations,
					"ExternalURL":       data.ExternalURL,
					"RuleUrl":           ruleURL,
					"AlertPageUrl":      alertPageURL,
				},
				To:          en.Addresses,
				SingleEmail: en.SingleEmail,
				Template:    "default_alert",
			},
		}
		// refer pkg/services/ngalert/schedule/compat.go
		if tmplErr != nil {
			en.log.Warn("failed to template email message", "err", tmplErr.Error())
		}
		if isNoDataAlert {
			cmd.Subject = "No Data Alert"
			cmd.Template = "no_data_alert"
		}
		if err := bus.Dispatch(ctx, cmd); err != nil {
			return false, err
		}
		return true, nil
	}
	dataAlerts := []ExtendedAlert{}
	noDataAlerts := []ExtendedAlert{}
	for _, alert := range data.Alerts {
		if alert.Labels["alertname"] == "DatasourceNoData" {
			newAlert := ExtendedAlert{}
			deepcopier.Copy(alert).To(&newAlert)
			noDataAlerts = append(noDataAlerts, newAlert)
		} else {
			newAlert := ExtendedAlert{}
			deepcopier.Copy(alert).To(&newAlert)
			dataAlerts = append(dataAlerts, newAlert)
		}
	}
	if len(dataAlerts) > 0 {
		newData := &ExtendedData{}
		deepcopier.Copy(data).To(newData)
		newData.Alerts = dataAlerts
		ok, err := Dispatcher(*newData, false)
		if !ok {
			return ok, err
		}
	}
	if len(noDataAlerts) > 0 {
		newData := &ExtendedData{}
		deepcopier.Copy(data).To(newData)
		newData.Alerts = noDataAlerts
		ok, err := Dispatcher(*newData, true)
		if !ok {
			return ok, err
		}
	}
	data.Alerts = ExtendedAlerts{}
	return true, nil
}

func (en *EmailNotifier) SendResolved() bool {
	return !en.GetDisableResolveMessage()
}