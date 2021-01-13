local t = (import 'github.com/open-cluster-management/kube-thanos/jsonnet/kube-thanos/thanos.libsonnet');
local loki = import 'github.com/observatorium/deployments/components/loki.libsonnet';
local config = import './operator-config.libsonnet';
local trc = import 'thanos-receive-controller/thanos-receive-controller.libsonnet';
local api = import 'observatorium/observatorium-api.libsonnet';
local obs = ((import 'github.com/observatorium/deployments/components/observatorium.libsonnet') + {
               config+:: config,
             } + (import 'github.com/observatorium/deployments/components/observatorium-configure.libsonnet'));

local patchObs = obs {
  compact+::
    t.compact.withVolumeClaimTemplate {
      config+:: obs.compact.config,
    } + (if std.objectHas(obs.compact.config, 'resources') then
      t.compact.withResources {
        config+:: {
          resources: obs.compact.config.resources,
        }
      } else {}
    ),
  
  rule+::
    t.rule.withVolumeClaimTemplate {
      config+:: obs.rule.config,
    } + (if std.objectHas(obs.rule.config, 'resources') then
      t.rule.withResources {
        config+:: {
          resources: obs.rule.config.resources,
        }
      } else {}
    ) + (if std.objectHas(obs.rule.config, 'alertmanagersURL') then 
      t.rule.withAlertmanagers {
        config+:: {
          alertmanagersURL: obs.rule.config.alertmanagersURL,
        }
      } else {}
    ) + (if std.objectHas(obs.rule.config, 'rulesConfig') then 
      t.rule.withRules {
        config+:: {
          rulesConfig: obs.rule.config.rulesConfig,
          reloaderImage: obs.rule.config.reloaderImage,
        }
      } else {}
    ),

  receivers+:: {
    [hashring.hashring]+:
      t.receive.withVolumeClaimTemplate {
        config+:: obs.receivers[hashring.hashring].config,
      } + (if std.objectHas(obs.receivers[hashring.hashring].config, 'resources') then
        t.receive.withResources {
          config+:: {
            resources: obs.receivers[hashring.hashring].config.resources,
          }
        } else {}
      )
    for hashring in obs.config.hashrings
  },

  store+:: {
    ['shard' + i]+:
      t.store.withVolumeClaimTemplate {
        config+:: obs.store['shard' + i].config,
      } + (if std.objectHas(obs.store['shard' + i].config, 'resources') then
        t.store.withResources {
          config+:: {
            resources: obs.store['shard' + i].config.resources,
          }
        } else {}
      )
    for i in std.range(0, obs.config.store.shards - 1)
  },

  loki+:: loki.withVolumeClaimTemplate {
    config+:: obs.loki.config,
  },

  query+:: 
    (if std.objectHas(obs.query.config, 'resources') then
      t.query.withResources {
        config+:: {
          resources: obs.query.config.resources,
        }
      } else {}
    ),

  queryFrontend+:: 
    (if std.objectHas(obs.queryFrontend.config, 'resources') then
      t.queryFrontend.withResources {
        config+:: {
          resources: obs.queryFrontend.config.resources,
        }
      } else {}
    ),

  thanosReceiveController+:: 
    (if std.objectHas(obs.thanosReceiveController.config, 'resources') then
       trc.withResources {
        config+:: {
          resources: obs.thanosReceiveController.config.resources,
        }
      } else {}
    ),

  api+:: 
    (if std.objectHas(obs.api.config, 'resources') then
       api.withResources {
        config+:: {
          resources: obs.api.config.resources,
        }
      } else {}
    ),

};
std.trace('cond is true returning '+ std.toString(obs.config.name), { a: false })

{
  manifests: std.mapWithKey(function(k, v) v {
    metadata+: {
      ownerReferences: [{
        apiVersion: config.apiVersion,
        blockOwnerdeletion: true,
        controller: true,
        kind: config.kind,
        name: config.name,
        uid: config.uid,
      }],
    },
    spec+: (
      if (std.objectHas(obs.config, 'nodeSelector') && (v.kind == 'StatefulSet' || v.kind == 'Deployment')) then {
        template+: {
          spec+:{
            nodeSelector: obs.config.nodeSelector,
          },
        },
      } else {}
    ) + (
      if (v.kind == 'StatefulSet' || v.kind == 'Deployment') then {
        template+: {
          spec+:{
            affinity: {
              podAntiAffinity: {
                preferredDuringSchedulingIgnoredDuringExecution: [
                  {
                    podAffinityTerm: {
                      labelSelector: {
                        matchExpressions:[
                          {
                            key: 'app.kubernetes.io/name',
                            operator: 'In',
                            values: [
                              v.metadata.labels['app.kubernetes.io/name'],
                            ],
                          },
                          {
                            key: 'app.kubernetes.io/instance',
                            operator: 'In',
                            values: [
                              v.metadata.labels['app.kubernetes.io/instance'],
                            ],
                          },
                        ],
                      },
                      topologyKey: "kubernetes.io/hostname",
                    },
                    weight: 30,
                  },
                  {
                    podAffinityTerm: {
                      labelSelector: {
                        matchExpressions:[
                          {
                            key: 'app.kubernetes.io/name',
                            operator: 'In',
                            values: [
                              v.metadata.labels['app.kubernetes.io/name'],
                            ],
                          },
                          {
                            key: 'app.kubernetes.io/instance',
                            operator: 'In',
                            values: [
                              v.metadata.labels['app.kubernetes.io/instance'],
                            ],
                          },
                        ],
                      },
                      topologyKey: "topology.kubernetes.io/zone",
                    },
                    weight: 70,
                  },
                ],
              },
            },
          },
        },
      } else {}
    ) + (
      if (std.objectHas(obs.config, 'affinity') && (v.kind == 'StatefulSet' || v.kind == 'Deployment')) then {
        template+: {
          spec+:{
            affinity+: obs.config.affinity,
          },
        },
      } else {}
    ) + (
      if (std.objectHas(obs.config.store.cache, 'exporterResources') && v.kind == 'StatefulSet' && v.metadata.name == obs.config.name + '-thanos-store-memcached') then {
        template+: {
          spec+:{
            containers: [
              if c.name == 'exporter' then c {
                resources: obs.config.store.cache.exporterResources,
              } else c
              for c in super.containers
            ],
          },
        },
      } else {}
    ) + (
      if (std.objectHas(obs.config.rule, 'reloaderResources') && (v.kind == 'StatefulSet') && v.metadata.name == obs.config.name + '-thanos-rule') then {
        template+: {
          spec+:{
            containers: [
              if c.name == 'configmap-reloader' then c {
                resources: obs.config.rule.reloaderResources,
              } else c
              for c in super.containers
            ],
          },
        },
      } else {}
    ),
  }, patchObs.manifests),
}
