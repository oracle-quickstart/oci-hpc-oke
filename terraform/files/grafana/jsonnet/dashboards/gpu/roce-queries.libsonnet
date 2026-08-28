local devicesByShape = [
  { shape: 'BM.GPU.H100.8', devices: 'mlx5_0|mlx5_1|mlx5_3|mlx5_4|mlx5_5|mlx5_6|mlx5_7|mlx5_8|mlx5_9|mlx5_10|mlx5_12|mlx5_13|mlx5_14|mlx5_15|mlx5_16|mlx5_17' },
  { shape: 'BM.GPU.H200.8', devices: 'mlx5_0|mlx5_3|mlx5_4|mlx5_5|mlx5_6|mlx5_9|mlx5_10|mlx5_11' },
  { shape: 'BM.GPU.RTXPRO.8', devices: 'mlx5_0|mlx5_1|mlx5_2|mlx5_3|mlx5_6|mlx5_7|mlx5_8|mlx5_9' },
  { shape: 'BM.GPU.B4.8', devices: 'mlx5_1|mlx5_2|mlx5_3|mlx5_4|mlx5_5|mlx5_6|mlx5_7|mlx5_8|mlx5_9|mlx5_10|mlx5_11|mlx5_12|mlx5_14|mlx5_15|mlx5_16|mlx5_17' },
  { shape: 'BM.GPU.A100-v2.8', devices: 'mlx5_1|mlx5_2|mlx5_3|mlx5_4|mlx5_5|mlx5_6|mlx5_7|mlx5_8|mlx5_9|mlx5_10|mlx5_11|mlx5_12|mlx5_14|mlx5_15|mlx5_16|mlx5_17' },
  { shape: 'BM.GPU4.8', devices: 'mlx5_0|mlx5_1|mlx5_2|mlx5_3|mlx5_6|mlx5_7|mlx5_8|mlx5_9|mlx5_10|mlx5_11|mlx5_12|mlx5_13|mlx5_14|mlx5_15|mlx5_16|mlx5_17' },
  { shape: 'BM.GPU.MI300X.8', devices: 'mlx5_0|mlx5_1|mlx5_2|mlx5_3|mlx5_4|mlx5_5|mlx5_6|mlx5_7|mlx5_8|mlx5_9' },
  { shape: 'BM.GPU.B200.8', devices: 'mlx5_0|mlx5_3|mlx5_4|mlx5_5|mlx5_6|mlx5_9|mlx5_10|mlx5_11' },
  { shape: 'BM.GPU.GB200.4', devices: 'mlx5_0|mlx5_1|mlx5_3|mlx5_4' },
  { shape: 'BM.GPU.GB200-v2.4', devices: 'mlx5_0|mlx5_1|mlx5_3|mlx5_4' },
  { shape: 'BM.GPU.GB200-v3.4', devices: 'mlx5_0|mlx5_1|mlx5_2|mlx5_3|mlx5_5|mlx5_6|mlx5_7|mlx5_8' },
  { shape: 'BM.GPU.GB300.4', devices: 'mlx5_0|mlx5_1|mlx5_2|mlx5_3|mlx5_5|mlx5_6|mlx5_7|mlx5_8' },
  { shape: 'BM.GPU.MI355X-v1.8', devices: 'mlx5_0|mlx5_1|mlx5_2|mlx5_3|mlx5_4|mlx5_5|mlx5_6|mlx5_7' },
  { shape: 'BM.GPU.MI355X.8', devices: 'mlx5_0|mlx5_1' },
  { shape: 'BM.GPU.B300.8', devices: 'mlx5_0|mlx5_1|mlx5_3|mlx5_4|mlx5_5|mlx5_6|mlx5_7|mlx5_8|mlx5_9|mlx5_10|mlx5_12|mlx5_13|mlx5_14|mlx5_15|mlx5_16|mlx5_17' },
];

local query(metric) = std.join('\nor\n', [
  'sum by (device) (irate(%s{hostname=~"$hostname", instance_shape="%s", device=~"%s"}[1m]))' % [
    metric,
    item.shape,
    item.devices,
  ]
  for item in devicesByShape
]);

local transmit = query('node_infiniband_port_data_transmitted_bytes_total');
local receive = query('node_infiniband_port_data_received_bytes_total');

{
  combined: '(\n%s\n)\n+\n(\n%s\n)' % [transmit, receive],
  transmit: transmit,
  receive: receive,
}
