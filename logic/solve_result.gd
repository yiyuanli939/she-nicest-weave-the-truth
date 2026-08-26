class_name SolveResult
extends RefCounted
## ProofGraph.solve() 的输出。UI 只依赖这个对象刷新,不碰求解过程。

enum EdgeStatus {
	OK,           ## 连线成立
	CONFLICT,     ## 合一冲突:两端纹样对不上(UI 画骷髅纹章)
	UNDERSPEC,    ## 欠定:纹样里还有未染纱,不算错但挡住胜利(问号线轴)
	CYCLE,        ## 在推理环上(衔尾蛇圈)
	ESCAPED_HYP,  ## 局部假设越界流到了结论(剪刀)
}

## 每个端口最终织出的纹样(已完全展开,可能仍含元变量)。
## 键 = Vector3i(节点 id, 0=输入口/1=输出口, 口下标)
var port_values: Dictionary = {}

## 每条边的状态。键 = 边 Vector4i,值 = EdgeStatus
var edge_status: Dictionary = {}

## 结论祖先链上还没接线的输入口,Vector2i(节点 id, 输入口下标)
var missing_inputs: Array[Vector2i] = []

## 整个证明是否完成
var solved: bool = false


func value_in(node_id: int, port: int) -> Formula:
	return port_values.get(Vector3i(node_id, 0, port))


func value_out(node_id: int, port: int) -> Formula:
	return port_values.get(Vector3i(node_id, 1, port))
