# GitHub & grafanabot automation

The bot is configured via [commands.json](https://github.com/tvarit-foggy/grafana/blob/main/.github/commands.json) and some other GitHub workflows [workflows](https://github.com/tvarit-foggy/grafana/tree/main/.github/workflows).

Label commands:

* Add label `bot/duplicate` the the bot will close with standard duplicate message and add label `type/duplicate`
* Add label `bot/needs more info` for bot to request more info (or use comment command mentioned above)
* Add label `bot/close feature request` for bot to close a feature request with standard message and adds label `not implemented`
* Add label `bot/no new info` for bot to close an issue where we asked for more info but has not received any updates in at least 14 days.
