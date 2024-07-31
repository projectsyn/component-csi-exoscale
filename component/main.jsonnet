local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local sc = import 'lib/storageclass.libsonnet';
local inv = kap.inventory();

local params = inv.parameters.csi_exoscale;
local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');

local namespace = kube.Namespace(params.namespace) {
  metadata+: {
    labels+: {
      'app.kubernetes.io/name': params.namespace,
      'pod-security.kubernetes.io/enforce': 'privileged',
      // Configure the namespaces so that the OCP4 cluster-monitoring
      // Prometheus can find the servicemonitors and rules.
      [if isOpenshift then 'openshift.io/cluster-monitoring']: 'true',
    },
  },
};

local exoscaleCred = kube.Secret('exoscale-credentials') {
  stringData: {
    EXOSCALE_API_KEY: params.apiSecret.accessKey,
    EXOSCALE_API_SECRET: params.apiSecret.secretKey,
  },
};

local storageClass = sc.storageClass('exoscale-sbs') {
  allowVolumeExpansion: true,
  provisioner: 'csi.exoscale.com',
  volumeBindingMode: 'WaitForFirstConsumer',
};

// Define outputs below
{
  '00_namespace': namespace,
  '20_credentials': exoscaleCred,
  '30_storage_class': storageClass,
}
