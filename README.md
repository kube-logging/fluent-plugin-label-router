# fluent-plugin-label-router

[Fluentd](https://fluentd.org/) output plugin to route records based on their Kubernetes metadata.

## Installation

### RubyGems

```
$ gem install fluent-plugin-label-router
```

### Specific install

```
$ gem install specific_install && gem specific_install -l https://github.com/banzaicloud/fluent-plugin-label-router.git
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
| @label | New @LABEL if selectors matched | nil |
| tag | New tag if selectors matched | "" |

## Examples

###1. Route specific `labels` and `namespace` to `@label` and new `tag`
Configuration to re-tag and re-label all logs from `default` namespace with label `app=nginx` and `env=dev`.
```
<match example.tag**>
  @type label_router
  <route>
     labels app:nginx,env:dev
     namespace default
     @label @NGINX
     tag new_tag
  </route>
</match>
```

#### Example records

Input
```ruby
@label = ""; tag = "raw.input"; {"log" => "", "kubernetes" => { "namespace_name" => "default", "labels" =>  {"app" => "nginx", "env" => "dev" } } }
@label = ""; tag = "raw.input"; {"log" => "", "kubernetes" => { "namespace_name" => "kube-system", "labels" =>  {"app" => "tiller" } } }

```

Output
```ruby
@label = "@NGINX"; tag = "new_tag"; {"log" => "", "kubernetes" => { "namespace_name" => "default", "labels" =>  {"app" => "nginx" } } }
nil
```
###2. Both `labels` and `namespace` are optional
Only `labels`
```
<match example.tag**>
  @type label_router
  <route>
     labels app:nginx
     @label @NGINX
     tag new_tag
  </route>
</match>
```
Only `namespace`
```
<match example.tag**>
  @type label_router
  <route>
     namespace default
     @label @NGINX
     tag new_tag
  </route>
</match>
```
Rewrite all
```
<match example.tag**>
  @type label_router
  <route>
     @label @NGINX
     tag new_tag
  </route>
</match>
```

### One of `@label` ot `tag` configuration should be specified
If you don't rewrite either of them fluent will **likely to crash** because it will reprocess the same messages again.

## Copyright

* Copyright(c) 2019- Banzai Cloud
* License
  * Apache License, Version 2.0
