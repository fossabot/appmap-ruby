# v0.23.0

* **appmap stats** command added.

# v0.22.0

* **RSpec** recorder generates an "inventory" (AppMap with classMap, without events) named `Inventory.appmap.json`.
* **appmap inspect** generates an inventory AppMap which includes `version`, `metadata`, and `classMap`. Previously, the file output by this command was the class map represented as an array.

# v0.21.0

* Scenario data includes `recorder` and `client` info, describing how the data was recorded.

# v0.20.0

Updated to [AppMap file format](https://github.com/applandinc/appmap) version 1.2.

* **Event `message`** is now an array of parameter objects.
* The value of each `appmap:` tags in an RSpec is recorded as a `label` in the AppMap file metadata.
* `layout` is removed from AppMap file metadata.

# v0.19.0

* **RSpec** feature and feature group names can be inferred from example group and example names.
* Stop using `ActiveSupport::Inflector.transliterate`, since it can cause exceptions.
* Handle StandardError which occurs while calling `#inspect` of an object.

# v0.18.1

* Now tested with Rails 4, 5, and 6.
* Now tested with Ruby 2.5 and 2.6.
* `explain_sql` is no longer collected.
* `appmap/railtie` is automatically required when running in a Rails environment.

# v0.17.0

**WARNING** Breaking changes

* **appmap upload** expects arguments `user` and `org`.
* **appmap upload** receives and retransmits the scenario batch id
* assigned by the server.

# v0.16.0

**WARNING** Breaking changes

* **Record button** removed. Frontend interactions are now recorded with a browser extension.
  As a result, `AppMap::Middleware::RecordButton` has been renamed to 
  `AppMap::Middleware::RemoteRecording`

# v0.15.1

* **Record button** moved to the bottom of the window.

# v0.15.0

**WARNING** Breaking changes

* **AppMap version** updated to 1.1
* **Event `parameters`** are reported as an array rather than a map, so that parameter order is preserved.
* **Event `receiver`** reports the `receiver/this/self` parameter of each method call.

# v0.14.1

* **RSpec recorder** won't try to modify a frozen string.

# v0.14.0

* **SQL queries** are reported for SQLite.

# v0.13.0

* **SQL queries** are reported for ActiveRecord.

# v0.12.0

* **Record button** integrates into any HTML UI and provides a button to record and upload AppMaps.

# v0.11.0

* Information about `language` and `frameworks` is provided in the AppMap `metadata`.

# v0.10.0

* **`AppMap::Algorithm::PruneClassMap`** prunes a class map so that only functions, classes and packages which are
  referenced by some event are retained.

# v0.9.0

* **`appmap/rspec`** only records trace events which happen during an example block. `before` and `after` events are
  excluded from the AppMap.
* **`appmap/rspec`** exports `feature` and `feature_group` attributes to the AppMap `metadata`
  section.

# v0.8.0

* **`appmap upload`** accepts multiple arguments, to upload multiple files in one command.

# v0.7.0

* **`appmap/railtie`** is provided to integrate AppMap recording into Rails apps.
  * Use `gem :appmap, require: %w[appmap appmap/railtie]` to activate.
  * Set Rails configuration setting `config.appmap.enabled = true` to enable recording of the app via the Railtie, and
    to enable recording of RSpec tests via `appmap/rspec`.
  * In a non-Rails environment, set `APPMAP=true` to to enable recording of RSpec tests.
* **SQL queries** are reported as AppMap event `sql_query` data.
* **`self` attribute** is removed from `call` events.

# v0.6.0

* **Web server requests and responses** through WEBrick are reported as AppMap event `http_server_request` data.
* **Rails `params` hash** is reported as an AppMap event `message` data.
* **Rails `request`** is reported as an AppMap event `http_server_request` data.

# v0.5.1

* **RSpec** test recorder is added.

# v0.5.0

* **'inspect', 'record' and 'upload' commands** are converted into a unified 'appmap' command with subcommands.
* **Config file name** is changed from .appmap.yml to appmap.yml.
* **`appmap.yml`** configuration format is updated.

# v0.4.0

Initial release.
