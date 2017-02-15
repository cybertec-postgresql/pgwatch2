## Conventions for adding dashboards

1. For a new dashboard create a new subdirectory in "grafana_dashboards". Folder name will serve as a Grafana "slug"
i.e. URL identifier so use hyphens for multi-word names.
2. Put the dashboard source in a file called dashboard.json (without the internal __inputs and __requires keys, i.e. exactly
as displayed after clicking on the "View JSON" button from Dashboard settings).
3. Put the title on a single line into a file called "title.txt". NB! Special characters like apostrophes need to be doubled (SQL syntax rules)

Stored dashboards will be installed when container starts up for the first time.
