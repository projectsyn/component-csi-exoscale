local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.csi_exoscale;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('csi-exoscale', params.namespace);

{
  'csi-exoscale': app,
}
