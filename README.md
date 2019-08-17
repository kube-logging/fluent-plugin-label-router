# fluent-plugin-label-router

[Fluentd](https://fluentd.org/) output plugin to route records based on their Kubernetes metadata.

## Installation

### RubyGems

```
$ gem install fluent-plugin-label-router
```

### Bundler

Add following line to your Gemfile:

```ruby
gem "fluent-plugin-label-router"
```

And then execute:

```
$ bundle
```

## Configuration

The configuration builds from `<route>` sections.

```
<match example.tag**>
  @type label_router
  <route>
     ...
  </route>
  <route>
     ...
  </route>
</match>
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| labels | Label definition to match record. Example: app:nginx  | nil |
| namespace | Namespaces definition to filter the record. Ignored if left empty. | "" |
| @labels | New @LABEL if selectors matched | nil |
| tag | New tag if selectors matched | "" |


## Copyright

* Copyright(c) 2019- Banzai Cloud
* License
  * Apache License, Version 2.0
