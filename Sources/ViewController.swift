import UIKit
import ARKit
import SceneKit

/// M1：AR 基础版
/// 后置摄像头全屏实时画面 + ARKit 平面检测（水平=地面 / 垂直=墙面）
/// 检测到的平面以半透明网格叠加，并用顶部状态栏给出识别反馈。
/// 墙面朝向由平面法线计算，以 8 向方位显示。
class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {

    private let sceneView = ARSCNView()
    private let statusLabel = UILabel()
    private let directionLabel = UILabel()

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSceneView()
        setupLabels()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startARSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    // MARK: - 界面搭建

    private func setupSceneView() {
        sceneView.frame = view.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.delegate = self
        sceneView.session.delegate = self
        view.addSubview(sceneView)
    }

    private func setupLabels() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        view.addSubview(statusLabel)

        directionLabel.translatesAutoresizingMaskIntoConstraints = false
        directionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        directionLabel.textColor = .systemOrange
        directionLabel.textAlignment = .center
        directionLabel.numberOfLines = 0
        directionLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        view.addSubview(directionLabel)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            directionLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            directionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            directionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    // MARK: - AR 会话

    private func startARSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            statusLabel.text = "当前设备不支持 AR 追踪"
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        statusLabel.text = "请缓慢移动手机，扫描周围环境…"
        directionLabel.text = "识别到墙面后将显示朝向"
    }

    // MARK: - ARSCNViewDelegate（平面可视化）

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        addPlaneNode(to: node, for: planeAnchor)
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor,
              let planeNode = node.childNodes.first,
              let plane = planeNode.geometry as? SCNPlane else { return }
        // 跟随平面扩展实时更新网格尺寸
        plane.width = CGFloat(planeAnchor.extent.x)
        plane.height = CGFloat(planeAnchor.extent.z)
        planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
    }

    private func addPlaneNode(to node: SCNNode, for planeAnchor: ARPlaneAnchor) {
        let plane = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
        let isVertical = planeAnchor.alignment == .vertical
        // 地面=绿色半透明，墙面=橙色半透明
        plane.materials.first?.diffuse.contents = isVertical
            ? UIColor.orange.withAlphaComponent(0.35)
            : UIColor.green.withAlphaComponent(0.35)
        let planeNode = SCNNode(geometry: plane)
        planeNode.name = isVertical ? "wall" : "floor"
        planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
        planeNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        node.addChildNode(planeNode)
    }

    // MARK: - ARSessionDelegate（识别反馈 + 朝向）

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        var horizontalCount = 0
        var verticalCount = 0
        var firstVertical: ARPlaneAnchor?

        for anchor in frame.anchors {
            guard let plane = anchor as? ARPlaneAnchor else { continue }
            if plane.alignment == .horizontal {
                horizontalCount += 1
            } else {
                verticalCount += 1
                if firstVertical == nil { firstVertical = plane }
            }
        }

        switch (horizontalCount, verticalCount) {
        case (0, 0):
            statusLabel.text = "请缓慢移动手机，扫描周围环境…"
        case (_, 0):
            statusLabel.text = "✓ 已识别地面 \(horizontalCount) 处，继续扫描找墙面…"
        case (0, _):
            statusLabel.text = "✓ 已识别墙面 \(verticalCount) 处，继续扫描找地面…"
        default:
            statusLabel.text = "✓ 已识别：地面 \(horizontalCount) 处 / 墙面 \(verticalCount) 处"
        }

        // 墙面朝向：由垂直平面法线计算方位角（8 向）
        if let wall = firstVertical {
            let wallNormal = SIMD3<Float>(wall.transform.columns.2.x,
                                          wall.transform.columns.2.y,
                                          wall.transform.columns.2.z)
            let nx = wallNormal.x
            let nz = wallNormal.z
            let angleDeg = (atan2(nx, nz) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            let direction = Self.eightDirection(angleDeg)
            directionLabel.text = "墙面朝向：\(direction)（法线方位 \(Int(angleDeg))°）"
        } else {
            directionLabel.text = "识别到墙面后将显示朝向"
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        statusLabel.text = "AR 会话出错：\(error.localizedDescription)"
    }

    func sessionWasInterrupted(_ session: ARSession) {
        statusLabel.text = "AR 会话被中断…"
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        statusLabel.text = "已恢复，请重新扫描…"
    }

    private static func eightDirection(_ degrees: Double) -> String {
        let dirs = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let index = Int((degrees + 22.5) / 45.0) % 8
        return dirs[index]
    }
}
