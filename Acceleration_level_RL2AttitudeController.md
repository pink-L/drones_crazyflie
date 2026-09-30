# Acceleration-Level RL + C3BF to Attitude Control

> **状态：架构草案，尚未实现。** 本文的加速度 C3BF、Crazyflie 姿态 PID 仿真、推力标定和实机跟踪误差界均是待完成工作。文中的 `safe` 表示滤波器按指定模型得到的候选指令；只有模型、可行域、采样延迟和跟踪误差条件得到验证后，才能讨论实际闭环安全保证。

## 1. 目标

本文档定义一套用于四旋翼无人机的控制链路：

```text
Observation
    ↓
Actor: z_policy（PPO 高斯样本）
    ↓
a_nom = a_bias + S_a tanh(z_policy)（世界系 m/s²）
    ↓
C3BF
    ↓
a_projected（残差合格时也记作 a_safe）
    ↓
Acceleration → Desired Thrust / Desired Attitude
    ↓
[roll_d, pitch_d, yawrate_d, thrust_cmd]
    ↓
Crazyflie-compatible Attitude PID (simulation / firmware)
    ↓
Rate Controller
    ↓
Mixer
    ↓
Motors
```

核心设计原则：

1. Actor/PPO 输出三维无界 latent action `z_policy`；确定性 action transform 才输出世界系净加速度 `a_nom`；Actor 不输出 yaw；
2. PPO 对 `z_policy` 计算 log-prob；CBF 处理有物理单位的 `a_nom`，输出最后候选 `a_projected`，残差合格时记为 `a_safe`；
3. CBF 只包含圆柱障碍约束，不加入六面 boundary；采用单约束解析投影、最多 10 轮、全约束残差验收，不用 QP 或 Dykstra；
4. yaw 不作为独立的 RL action；
5. 第一版在实机地面以零推力同步固件 yaw 目标，随后保持同一个世界系 `psi_hold^W`，发送零 `yawrate_cmd`；仿真 reset 单独初始化；
6. 边界由独立的 `r_boundary` 学习信号和物理越界终止处理；最终由执行候选与一致的航向参考生成 roll/pitch、yawrate 与整数推力命令。

---

## 2. Actor 输出

PPO 的动作变量是三维无界高斯样本，不直接具有加速度单位：

$$
\mathbf z_k\sim\pi_\theta(\cdot\mid s_k),\qquad
\boxed{\mathbf a_{\rm nom,k}=\mathbf a_{\rm bias}+S_a\tanh(\mathbf z_k)}
$$

第一版固定 `S_a=diag(s_x,s_y,s_z)`、`a_bias=0`，三个正尺度由 NavAcc 配置给出。`a_nom` 是**世界系净平动加速度，单位 m/s²**，所以悬停的名义加速度为零；只有后续明确改变动作范围时才重新设计 bias。这一 `tanh` 映射是 NavAcc 的新设计；现有 NavVel 速度 transform 使用模长限幅，不应描述为已有的 `tanh` 行为。数据链为：

```text
policy action z_policy [3] → a_nom [3, m/s²] → obstacle C3BF → a_projected [3, m/s²]（valid 时 a_safe）
```

PPO 的 `sample_log_prob`、ratio 和策略损失只针对 `z_policy`；CBF correction 定义为 `a_projected-a_nom`，并附 `valid` 状态，新任务的名义动作平滑项默认用相邻外环的 `a_nom` 差分，不能把 `z_policy` 与 `a_safe` 混为一种动作。若另设执行动作或电机平滑项，须单独命名和计权。reset 时清除上一动作记录。

Actor 不直接输出：

```text
yaw
yaw_rate
roll
pitch
thrust
velocity
```

`a_nom` 的三轴由同一个 Actor 产生，但圆柱障碍的 CBF 行只约束水平分量；竖直分量仍须经过可执行范围检查。

---

## 3. C3BF Safety Filter

CBF 输入是第 2 节的 `a_nom`。最多 10 轮后固定以**最后一次迭代结果** `a_projected` 作为最终投影候选；只有全部约束残差合格时才允许称为 `a_safe`：

$$
\boxed{\mathbf a_{\mathrm{nom}}\xrightarrow[\text{最多 10 轮}]{\text{解析单集合投影}}\mathbf a_{\mathrm{projected}}}
$$

残差合格时才令 `a_safe=a_projected`，其三维形式为：

$$
\boxed{
\mathbf a_{\mathrm{safe}}
=
\begin{bmatrix}
a_x\\
a_y\\
a_z
\end{bmatrix}
}
$$

其中：

* \(a_x\)：世界坐标系 \(x\) 方向安全加速度；
* \(a_y\)：世界坐标系 \(y\) 方向安全加速度；
* \(a_z\)：世界坐标系 \(z\) 方向安全加速度。

从这一层开始，后续控制器都应尽可能跟踪：

$$
\mathbf a_{\mathrm{safe}}
$$

而不是 `a_nom` 或高斯样本 `z_policy`。

### 与当前 OmniDrones C3BF 的区别（必须实现）

当前 `omni_drones/utils/c3bf.py` 使用速度指令 `u` 和一阶速度环 `dot(v)=(u-v)/tau`，不能把原来的 `u` 直接改名为加速度。新模块只重推**水平圆柱障碍**碰撞锥及低速距离 HOCBF；`safety_boundaries.py` 的六面速度环约束**不接入新 CBF**。工作空间由第 24 节的独立奖励与环境终止负责，不宣称硬边界安全保证。

每个柱体的 CBF 半径固定为

$$
R_i=r_{{\rm cyl},i}+r_{{\rm uav},xy}+d_{safe},
$$

其中 `r_cyl,i` 为该柱的逻辑 XY 半径，`r_uav,xy` 为机体水平包络半径，`d_safe` 是唯一的额外安全余量，包含所需 inflation；不得在别处重复累加。静态柱与动态柱使用同一规则，本版已取消矮柱。碰撞/奖励可使用各自明示的几何阈值，但必须与 CBF 半径区分。

例如沿用当前水平碰撞锥定义，令 `p=p_obs-p_uav`、`w=v_obs-v_uav`、
`rho=sqrt(||p||²-R_i²)`、`h=p·w+rho||w||`，在非退化的 `||w||>0` 区间取
`q=p+rho w/||w||`。若实际平动模型为 `dot(v_uav)=a_safe+e_a`，则

$$
\dot h=\|w\|^2+\frac{\|w\|}{\rho}p\cdot w
       +q\cdot(a_{obs}-a_{safe}-e_a).
$$

因此 `dot(h)+gamma h>=0` 给出关于 **加速度** 的半空间：

$$
q\cdot a_{safe}\leq
\|w\|^2+\frac{\|w\|}{\rho}p\cdot w
+q\cdot\hat a_{obs}+\gamma h
-\|q\|(\epsilon_{obs}+\epsilon_{track}).
$$

这里 `p,w,q` 都是 **XY 二维量**；静态柱的 `v_obs=a_obs=0`，动态柱仅有 XY 运动，须用估计值而非仿真真值进入运行时 CBF。误差界必须覆盖障碍加速度估计误差和本机加速度跟踪误差；位置、速度误差及采样/通信延迟另计。

**静态柱不自动意味着相对速度为零。** 对静态柱 `w=-v_uav,xy`；只有无人机水平速度也接近零时碰撞锥才低速退化。动态柱若与无人机同速也会退化。因此按 `||w||` 切换，静态/动态标签只用于障碍自身速度/加速度。不能靠分母加 epsilon 继续宣称碰撞锥有效。定义 `h_d=p·p-R_i²`、`dot(h_d)=2p·w`、`psi_1=dot(h_d)+lambda_1 h_d`，则加速度控制下的距离 HOCBF 行为：

$$
p\cdot a_{safe}\leq\|w\|^2+p\cdot\hat a_{obs}
+(\lambda_1+\lambda_2)p\cdot w
+\frac{\lambda_1\lambda_2}{2}h_d
-\|p\|(\epsilon_{obs}+\epsilon_{track}).
$$

**第一版分支规则固定：静态柱始终使用距离 HOCBF；动态柱在 `||w||≤w_off` 时进入距离 HOCBF，在 `||w||≥w_on` 时退出并使用 C3BF，区间内保持原分支，且 `w_on>w_off>speed_epsilon`。** 每柱独立维护切换状态，reset 清空。静态柱选择 HOCBF 是实现选择，而非“静态柱必有 `w=0`”的推论。两种屏障的安全集合不必相同，动态柱切换时须检查将进入分支的 `h_d≥0`、`psi_1≥0` 或 C3BF `h≥0`；不满足则标记恢复/未验证状态，不能仅靠滞回来证明切换安全。`||p||<R_i`、`rho≈0`、`psi_1<0` 和状态过期均有单独状态：可记录恢复约束，但不得宣称前向不变性。等号 `||p||=R_i` 是几何边界，是否保守判失败由新任务配置明确决定。

**运行时投影契约：**仅采用每个半空间/选定物理集合的闭式投影，按最违反约束选择，初始检查后最多执行 **10 轮**；不调用 QP 求解器，不调用 Dykstra，不设置额外 continuation。每轮和最终都检查原始单位下的全部障碍行及第 22 节选定的物理约束。到第 10 轮仍未满足全部残差时立即停止，以第 10 轮 `a_projected` 为最终候选并返回 `ITERATION_LIMIT`、实际残差和 `valid=false`；不得继续求解、清零或声称已满足 CBF。仿真训练可以记录并执行这个有限候选以评估失败后果；状态过期、非有限或物理执行域无效则仍须拒绝。实机若要使用该候选，需单独验证失效处置，不能把它当成安全保证。

单个半空间的投影有解析式 `P_{A_i a<=b_i}(x)=x-max(0,(A_i·x-b_i)/||A_i||²)A_i`。**多约束下的 10 轮序列只是由解析步骤组成的有限迭代可行性修正，通常不是联合集合的精确欧氏投影解析解。**文档中的“最小修正”只作为设计目标；验收依据是最终可行残差与明确的修正量，不声称全局最优。圆柱数增加时尤其要统计迭代上限失败率。

---

## 4. 四旋翼平移动力学

先采用如下坐标约定：

* 世界坐标系 \(z\) 轴向上；
* 总推力沿机体 \(+z\) 轴；
* \(R\) 表示 body frame 到 world frame 的旋转矩阵。

定义：

$$
e_3=
\begin{bmatrix}
0\\
0\\
1
\end{bmatrix}
$$

四旋翼平移动力学为：

$$
\boxed{
m\ddot{\mathbf p}
=
T R e_3
-
mg e_3
}
$$

其中：

* \(m\)：无人机质量；
* \(T\)：总推力；
* \(R\)：姿态旋转矩阵；
* \(Re_3\)：机体 \(z\) 轴在世界坐标系中的方向。

令：

$$
\ddot{\mathbf p}
=
\mathbf a_{\mathrm{safe}}
$$

则：

$$
m\mathbf a_{\mathrm{safe}}
=
T R e_3
-
mg e_3.
$$

移项：

$$
\boxed{
TR e_3
=
m
\left(
\mathbf a_{\mathrm{safe}}
+
ge_3
\right)
}
$$

因此安全加速度实际上决定了期望总推力向量。

---

## 5. Safe Acceleration → Desired Thrust

定义：

$$
\mathbf f_d
=
m
\left(
\mathbf a_{\mathrm{safe}}
+
ge_3
\right)
$$

即：

$$
\boxed{
\mathbf f_d
=
m
\begin{bmatrix}
a_x\\
a_y\\
a_z+g
\end{bmatrix}
}
$$

期望总推力大小：

$$
\boxed{
T_d
=
\|\mathbf f_d\|
}
$$

因此：

$$
\boxed{
T_d
=
m
\sqrt{
a_x^2
+
a_y^2
+
(a_z+g)^2
}
}
$$

---

## 6. Safe Acceleration → Desired Body Z Axis

因为总推力只能沿机体 \(z\) 轴产生，因此期望机体 \(z\) 轴必须与期望推力方向一致。

定义：

$$
\boxed{
\mathbf b_{3d}
=
\frac{
\mathbf a_{\mathrm{safe}}
+
ge_3
}{
\left\|
\mathbf a_{\mathrm{safe}}
+
ge_3
\right\|
}
}
$$

即：

$$
\boxed{
\mathbf b_{3d}
=
\frac{
\begin{bmatrix}
a_x\\
a_y\\
a_z+g
\end{bmatrix}
}{
\sqrt{
a_x^2+a_y^2+(a_z+g)^2
}
}
}
$$

其中：

$$
\mathbf b_{3d}
$$

就是期望机体 \(z\) 轴在世界坐标系中的方向。

---

## 7. 为什么仅靠加速度还不能得到完整姿态

三维加速度确定：

$$
\mathbf b_{3d}
$$

也就是确定了推力方向。

但是四旋翼仍然可以绕：

$$
\mathbf b_{3d}
$$

旋转。

因此仅靠：

$$
a_x,a_y,a_z
$$

不能唯一确定完整的：

$$
R_d.
$$

还需要指定一个 heading，也就是：

$$
\boxed{
\psi_d
}
$$

因此完整姿态由：

$$
\boxed{
\mathbf b_{3d}
+
\psi_d
}
$$

共同决定。

---

## 8. yaw 不作为 Actor Action

Actor/PPO 固定输出三维 `z_policy`，确定性 action transform 生成 `[a_nom,x, a_nom,y, a_nom,z]`；yaw 由独立、确定性的 heading 模块管理。这是减少策略维度的设计选择，不是“yaw 不影响安全”的证明：yaw 会影响可见方向、roll/pitch 指令的坐标变换和电机余量。当前水平柱形障碍 C3BF 不直接约束 yaw；heading 模块仍要遵守限幅、复位与跟踪误差契约。

---

## 9. 当前速度与 yaw 的关系

当前估计速度可用于生成期望运动方向，但 `atan2(v_y,v_x)` 在低速时没有稳定意义。状态估计和通信具有延迟，控制计算必须使用与 CBF 同一时间戳的估计，并在误差预算中计入延迟。运动方向 heading 是一个**候选目标**，不等同于机体当前 yaw，也不等同于固件内部的 yaw setpoint。

---

## 10. 使用 Safe Acceleration 构造候选运动方向

运动方向 yaw 的默认候选由**水平速度**给出，只有第 13 节的速度门限允许更新时才计算：

$$
v_{xy}=\sqrt{v_x^2+v_y^2},\qquad
\psi_{motion}=\operatorname{atan2}(v_y,v_x).
$$

也可研究一阶预测 `v_pred=v_k+a_safe Δt`，但这是另一种候选定义，需单独验证预测误差和速度门限：

$$
\psi_{motion,k}=\operatorname{atan2}(v_{y,k}+a_y\Delta t,\;v_{x,k}+a_x\Delta t).
$$

它假定加速度在预测窗口内被跟踪，且没有自动生成与之严格一致的 yawrate。该预测的误差来自姿态/推力滞后、扰动与状态估计误差，不得直接作为 CBF 保证的依据。第一版完全不启用运动方向 yaw。

---

## 11. 第一版推荐 yaw 策略

第一版全程采用 `HEADING_HOLD`，以**同一个航向参考**生成 roll/pitch，并驱动固件 yaw 环。这里区分三个量：外部参考航向的导数 `dot(psi_ref)`、固件姿态 PID 输出的期望机体 yaw rate `r_des`、传感器测得的实际机体 yaw rate `r_actual`。在非水平姿态下，欧拉 yaw 导数也不能直接等同于机体 `r`。

传统 RPYT 模式下，固件在 yaw `modeVelocity` 中积分 `setpoint->attitudeRate.yaw`，得到内部 `attitudeDesired.yaw`；再由 yaw 姿态 PID 产生 `rateDesired.yaw`，最后由 rate PID 跟踪。因此 `yawrate_cmd=0` 表示**冻结固件期望航向**，不表示内环 `r_des=0` 或实际 `r_actual=0`。有 yaw 扰动时，姿态 PID 仍可输出非零 `r_des` 来恢复航向。

第一版的**实机地面**初始化顺序是：发送零推力 RPYT 包完成低层 commander 解锁流程，让固件至少执行一次零推力控制更新；该路径会复位 PID 并令固件内部 `attitudeDesired.yaw = state->attitude.yaw`。在这一同步时刻记录统一世界系航向 `psi_hold^W=measured_yaw^W`，比较固件日志时使用显式 `world_yaw_to_firmware_yaw()`。**仿真 episode reset** 直接初始化 PID、内部 yaw 参考与电机状态，不额外推进零推力物理步；现有 NavVel 从空中位置开始且电机初始化为悬停附近，新任务的空中 reset 与实机地面解锁要分别定义。起飞和飞行中用 `psi_cmd=psi_hold^W` 构造 `R_d`，持续发送 `yawrate_cmd=0`。**不要在飞行中使用每次更新的 `measured_yaw` 替代 `psi_hold^W`**，否则构造倾角和固件跟踪的 yaw 目标可能不同。零推力同步是地面初始化动作，不能在飞行中当作纠偏手段。

这套方案仍需用固件 `controller.yaw` 日志或等效接口校验实际内部 yaw 目标；固件有 yaw 目标限差、命令丢失、模式切换等机制，外部 `psi_hold^W` 不会自动保持绝对一致。若目标偏差超过验证界限，应进入明确的失效/恢复状态，并把可接受的航向误差对加速度跟踪的影响计入 `e_a`。

---

## 12. 后续可选的运动方向 yaw 控制

若任务需要机头朝向运动方向，可将第 10 节的 `psi_motion` 作为候选参考，但必须维护**一个**连续的 `psi_ref` 状态。每个 100 Hz 控制步先对角度差做 wrap，再限制参考增量：

$$
\Delta\psi_k=\operatorname{clip}(\operatorname{wrap}(\psi_{motion,k}-\psi_{ref,k}),
-\omega_{max}\Delta t,\omega_{max}\Delta t),
\qquad\psi_{ref,k+1}=\operatorname{wrap}(\psi_{ref,k}+\Delta\psi_k).
$$

在统一的世界 yaw 正方向定义下，目标参考变化率为 `omega_ref = Δpsi_k/Δt`。实际传给 `send_setpoint` 的 `yawrate_cmd` 必须先经过已验证的坐标系和符号转换：`yawrate_cmd = world_yaw_rate_to_api(omega_ref)`。legacy RPYT 接收端对 API yawrate 取反，因此不能未经验证就写成 `yawrate_cmd = omega_ref`。**同一个** `psi_ref` 用于构造 `R_d`。应记录/读取固件内部 yaw 目标并检查其与外部积分参考的偏差；角度限差、丢包、复位或模式切换可让两者分离。无法维持同步时不启用 `MOTION_HEADING`。

解析式 `(v_x a_y-v_y a_x)/(v_x²+v_y²)` 只是理想连续模型下**当前速度方向**的瞬时变化率，分母在低水平速度时退化；它不是上述限速离散参考的命令。可保留用于理论解释，不作为实现主路径。

---

## 13. 低速和复位处理

`atan2(v_y,v_x)` 在 `v_xy→0` 时代表的运动方向没有定义，因此门限必须作用于**水平速度** `v_xy`，不能用三维 `||v||`；刚起飞时较大的 `v_z` 不意味着水平 heading 可用。后续可选的状态机如下；第一版始终停留在 `HEADING_HOLD`。

```text
GROUND_SYNC: 实机地面零推力同步固件 yaw 目标，记录 psi_hold^W；未验证同步则不进入飞行
TAKEOFF_HOLD: psi_ref^W=psi_hold^W，yawrate_cmd=0
    v_xy > v_on 持续 N_on 个 100 Hz 周期 → MOTION_HEADING
MOTION_HEADING: 按第 12 节限速更新 psi_ref 和 API yawrate_cmd
    v_xy < v_off 持续 N_off 个周期 → LOW_SPEED_HOLD
LOW_SPEED_HOLD: 冻结当前 psi_ref，yawrate_cmd=0
    v_xy > v_on 持续 N_on 个周期 → MOTION_HEADING
```

要求 `v_on>v_off`，且进入/退出计数和阈值由状态估计噪声标定。`v_off=0.10 m/s`、`v_on=0.20 m/s` 仅可作仿真试验初值，并非 Crazyflie 或本项目既有参数。小噪声近似下，航向噪声标准差约 `sigma_psi≈sigma_v_perp/v_xy`；若 `sigma_v≈0.03 m/s` 且允许 `10°≈0.174 rad`，参考门限量级约 `0.17 m/s`，实际值仍须从日志确定。reset 同时清除计数、yaw 参考、PID、滤波及时间戳；状态过期、推力向量或姿态构造退化时进入显式失效处理。

---

## 14. yaw 物理限制

yaw 角度增量、yawrate、yaw 加速度和机体/电机余量都要限制。单独裁剪 yawrate 不会限制直接由 `atan2` 更新的 yaw 角，也不会保证 roll/pitch 与机体实际 yaw 一致。heading 约束属于执行可行性约束，若影响加速度跟踪，其误差要进入 CBF 的鲁棒裕量。

---

## 15. 使用 b3d 和 yaw 构造期望姿态

令 `psi_cmd` 为本次实际用于 roll/pitch 转换的世界系 heading：第一版为 reset 后固定的 `psi_hold^W`；未来的运动方向模式为与固件目标保持同步的 `psi_ref^W`。为取得与 ZYX 欧拉 yaw 一致的姿态，在 `b3d,z>0` 且最大倾角小于 90° 时定义

$$
\mathbf b_{2c}=(-\sin\psi_{cmd},\cos\psi_{cmd},0),\quad
\mathbf b_{1d}=\frac{\mathbf b_{2c}\times\mathbf b_{3d}}
{\|\mathbf b_{2c}\times\mathbf b_{3d}\|},\quad
\mathbf b_{2d}=\mathbf b_{3d}\times\mathbf b_{1d},\quad
R_d=[\mathbf b_{1d},\mathbf b_{2d},\mathbf b_{3d}].
$$

这给出右手正交姿态，并使从 `R_d` 提取的 ZYX yaw 与 `psi_cmd` 一致。常见的 `b2d=normalize(b3d×[cos(psi),sin(psi),0])` 是另一种合法的几何 heading 构造，但其最终 ZYX 欧拉 yaw 一般不严格等于输入 `psi`；两种构造不能在接口中混用。若推力向量接近零或交叉乘积退化，应进入明确的无效/恢复状态。

---

## 16. R_d、T_d 到 Crazyflie 指令

仿真和实机共同约定最终命令为

```text
[roll_cmd_deg, pitch_cmd_deg, yawrate_cmd_deg_s, thrust_cmd_uint16]
```

用 `R_d` 按约定的 ZYX 欧拉顺序提取 roll/pitch，转为度；`yawrate_cmd` 第一版为零，运动方向模式由同一 `psi_ref` 的限速增量经接口符号转换得到。`T_d` 是牛顿，不能直接当作 `send_setpoint` 的 thrust 整数；必须标定目标质量、电机/桨、固件配置、实际启用的电池补偿、供电状态与 PWM/推力非线性，建立 `thrust_cmd ↔ 实际总推力` 的有效范围和饱和处理。固件的电池补偿视配置而定，不应在仿真或外部跟踪器中未经核对再叠加一层电压校正。仿真端以**API 调用前**的四元命令为共同接口，逐项复现 cflib 和固件的符号处理：cflib 打包时反转 pitch，legacy RPYT 固件接收端对 yawrate 取反，后续控制/混控还有符号约定；不能只复制其中一步。

`send_setpoint` 只传 roll、pitch、yawrate、thrust，不接受完整 `R_d` 或 yaw 角。实机姿态和角速度 PID 在固件中执行；仿真端必须新建与其输入、符号、复位、积分/滤波、输出混控和时间步相匹配的控制链。当前 OmniDrones 的 `AttitudeController` 是另一种姿态反馈实现，当前 `PIDrate` 也只有角速度 PID，均不能仅凭名称当作固件姿态 PID。

NavAcc 第一版的动作接口冻结为：

| 层 | 张量契约 | 单位与顺序 |
|---|---|---|
| PPO 可见 `z_policy` | `float32 [B,1,3]`，无界 | 三维 latent；PPO 在此计算 log-prob |
| transform 输出 `a_nom` | `float32 [B,1,3]` | 世界系净加速度 `[a_x,a_y,a_z]`，m/s² |
| NavAcc base-env `rpyt_api` | `float32 [B,1,4]`，外环保持 10 ms | `[roll_deg,pitch_deg,yawrate_deg_s,thrust_uint16_value]`，末项在 float32 中存整数值 |
| `CrazyflieFirmwarePID` 输出 | `float32 [B,1,4]`，每 2 ms 更新 | 与 `drone.apply_action()` 一致的归一化旋翼命令 `[-1,1]` |

仿真与实机都在 API 边界执行 `thrust_uint16=round(clip(force_to_commander(T_d),0,65535))`，随后再按已标定的有效飞行区间检查；`0` 仅用于实机地面解锁/停机流程。float32 可精确表示该范围的所有整数，base env 虽以 float32 存储，也不得把推力重新当连续牛顿量。测试包括 0、有效区间端点、65535 与小数半格的量化/饱和行为。

---

## 17. 完整执行链与频率

```text
每 10 ms 外环一次：读取观测 → PPO 样本 z_policy → a_nom → 最多 10 轮解析投影 a_projected
                 → heading 状态 → 加速度到姿态/推力转换 → 保持 RPYT 命令
其后 5 × 2 ms 物理子步：每步读取最新姿态和 gyro → 固件兼容 attitude PID
                 → rate PID → mixer → motor dynamics → rotor 力/矩 → PhysX
```

固件文档给出的姿态和角速度 PID 均为约 500 Hz。**当前项目使用自己的 `IsaacEnv`，不是 Isaac Lab `decimation` 配置接口。**当前 `NavVel.yaml` 为 `sim.dt=0.01, sim.substeps=1`；NavAcc 目标配置为 `sim.dt=0.002` 秒、`sim.substeps=5`，从而 `dt_env=sim.dt×sim.substeps=0.01` 秒。`IsaacEnv._step` 在每个子步调用 `_pre_sim_step`，当前 NavVel 路径在外环已把动作变成旋翼指令，子步会重复该指令。NavAcc 应在 TorchRL inverse transform 每外环仅运行一次 `z_policy→a_nom→CBF→RPYT`，把保持的 API 级 RPYT 送入 base env；`NavAcc._pre_sim_step` 每个子步读取最新姿态/gyro 并运行固件兼容 PID、混控、电机与 `drone.apply_action()`。不得把 Actor、CBF、heading 或加速度转换放进 `_pre_sim_step` 重算。仅改配置值不会自动得到 500 Hz 内环。

`CrazyflieFirmwarePID` 是**待实现的仿真控制器**，不能只套现有 `AttitudeController` 名称。以部署实机的固定固件提交和控制参数为基准，复现 `controller_pid.c` 的 RPYT 模式/内部 yaw 参考、`attitude_pid_controller.c` 的 roll/pitch/yaw 姿态 PID 与角速度 PID，以及对应的输出符号、积分复位/限幅、混控、电机响应和零推力状态。每个 2 ms 子步使用保持的 `rpyt_api` 和最新姿态/gyro，重新计算 rate setpoint、力矩与四电机命令；只缓存 10 ms 外环 setpoint，不缓存 PID 输出。仿真 reset 要分别重置 yaw 参考、积分器、滤波器和电机初态，并与实机地面零推力初始化区分。先以相同 RPYT 阶跃、yaw 扰动和推力变化比较固件日志与仿真轨迹，再将其用于 RL 训练。

还需核查子步中障碍运动、旋翼电机时间常数、reset/终止与观测时间戳：当前障碍运动按物理 `dt` 更新，奖励/观测按外环步评估。仿真外环频率只是目标频率；实机还需记录观测、计算、发包、固件接收和执行时间戳，测量采样保持、无线丢包及延迟。

---

## 18. Mathematical Summary

下列式子使用世界系 z 向上、机体推力沿 +body-z、`a_safe` 表示**净平动加速度**的约定：

$$
\begin{aligned}
\mathbf z&\sim\pi_\theta(\cdot\mid s),\qquad \mathbf a_{nom}=\mathbf a_{bias}+S_a\tanh(\mathbf z),\\
\mathbf a_{projected}&=\operatorname{AnalyticProject10}_{\mathcal C_{obstacle}\cap\mathcal A_{physical}}(\mathbf a_{nom}),\\
\mathbf f_d&=m(\mathbf a_{projected}+g\mathbf e_3),\\
T_d&=\|\mathbf f_d\|,\qquad \mathbf b_{3d}=\mathbf f_d/T_d.
\end{aligned}
$$

残差合格时 `a_safe=a_projected`；迭代超限时只保留最后候选及未验证标志。`T_d=0` 时方向未定义；物理可行域和失败处理必须排除或显式处理它。`R_d` 按第 15 节由 `b3d` 和一致的 `psi_cmd` 构造。第一版完成实机地面同步或仿真 reset 后，取 `psi_cmd=psi_hold^W`、发送 `yawrate_cmd=0`。最终输出是第 16 节的 Crazyflie 四元命令，而非抽象的 `(R_d,T_d)`。

`AnalyticProject10` 表示最多 10 次单集合闭式投影，迭代上限时保留最后一次候选并标记残差状态；它不是精确欧氏投影算子，也不包含六面 boundary。仅当残差验收通过、`a_safe=a_projected` 时，实际闭环可按

$$
\dot{\mathbf v}=\mathbf a_{safe}+\mathbf e_a
$$

评估，其中 `e_a` 包含姿态/电机滞后、推力映射误差、扰动和离散保持效应。验收失败时执行量记作 `a_projected`，不得在该式中将其写成 `a_safe`。只有给出并验证相关误差界、初始安全集合和求解可行性，才能把滤波结果解释为安全保证。

---

## 19. 推荐的伪代码（第一版）

```text
实机地面初始化:
    send_zero_thrust_setpoint_for_unlock_and_yaw_sync()
    wait_until_firmware_control_update_has_processed_zero_thrust()
    psi_hold_W = measured_world_yaw_at_sync
    require verified_firmware_yaw_target_matches(world_yaw_to_firmware_yaw(psi_hold_W))

仿真 episode reset:
    reset attitude/rate PID, firmware yaw reference, motor state, filters and timestamps
    psi_hold_W = measured_world_yaw_at_reset
    firmware_yaw_reference = world_yaw_to_firmware_yaw(psi_hold_W)
    # 空中 reset 的电机初值另定；不额外推进零推力 physics step

首次进入控制环:
    heading_mode = HEADING_HOLD

每个 100 Hz 外环周期:
    state = time-aligned state estimate
    z_policy = actor_sample(state)          # PPO Gaussian action, shape [3]
    a_nom = a_bias + S_a * tanh(z_policy)  # world m/s²
    result = acceleration_cbf_project(
        state, a_nom,
        xy_cylinder_obstacle_constraints,
        analytic_physical_inner_set,
        tracking_error_bound,
        backend='greedy_analytic', max_iters=10, continuation=0,
    )
    if result is stale, nonfinite or physically_invalid:
        enter_explicit_recovery_or_abort_state()
    a_projected = result.last_iterate       # 最多 10 轮，不再继续求解或清零
    if result.all_residuals_pass:
        a_safe = a_projected               # 可使用 safe 名称
    else:
        record_iteration_limit_and_residuals()
        mark_unverified_command()          # 仿真可执行最后候选；实机另需失效监控
    a_exec = a_projected

    f_des = mass * (a_exec + [0, 0, gravity])
    require norm(f_des) > force_epsilon
    thrust_N = norm(f_des)
    b3_des = f_des / thrust_N
    require feasible_thrust_and_tilt(b3_des, thrust_N)

    require validated_bound(firmware_yaw_target - world_yaw_to_firmware_yaw(psi_hold_W))
    psi_cmd = psi_hold_W
    yawrate_cmd = 0                        # 冻结 yaw angle reference，不是 r_des=0
    R_des = construct_ZYX_yaw_consistent_attitude(b3_des, psi_cmd)
    roll_deg, pitch_deg = extract_ZYX_roll_pitch(R_des)
    thrust_uint16 = calibrated_force_to_commander_thrust(thrust_N)
    send_or_simulate_setpoint(roll_deg, pitch_deg, yawrate_cmd, thrust_uint16)

每个 2 ms 仿真物理子步 / 实机固件周期:
    read_current_attitude_and_gyro()
    firmware_yaw_reference_update(held_RPYT_setpoint)
    attitude_PID -> rate_PID -> mixer -> motor dynamics -> apply_rotor_forces()
    # 仅保持外环 RPYT setpoint；状态与电机输出每个子步都更新
```

后续加入运动方向 yaw 时，按第 12–13 节用水平速度滞回状态机替换 `psi_cmd/yawrate_cmd` 两行，并持续验证固件内部 yaw 目标与外部参考的关系。上面的固件更新是仿真链路需要复现的语义；实机执行由固件自行完成。`r_boundary` 在环境奖励阶段根据执行后的状态计算，不改变 `a_safe`，不能作为硬边界 CBF 保证。

---

## 20. 推荐的软件模块划分及当前项目改动面

| 模块 | 输出和责任 | 当前状态 |
|---|---|---|
| `NavAcc` / `NavAcc.yaml` | 三维 PPO 样本 `z_policy`、物理 `a_nom`、独立 `r_boundary`、圆柱课程和观测 | **新建**任务和配置；NavVel 的四维速度/yaw baseline、配置和旧 checkpoint 保持行为兼容 |
| `AccelerationC3BF` | 仅 XY 圆柱障碍行、低速 HOCBF、最多 10 轮解析可行性投影及失败状态 | **新建**；当前 `c3bf.py` 和 `safety_projection.py` 均是速度语义，六面 `safety_boundaries.py` 不接入 |
| `AccelerationToRPYT` / Heading | `a_projected`、世界系 yaw 参考、质量与推力标定 → 四元 Crazyflie API 命令 | **新建**；第一版固定 `HEADING_HOLD` |
| `CrazyflieFirmwarePID` | 每个 2 ms 子步读取新状态，运行 yaw 参考积分、姿态 PID、rate PID、混控和电机模型 | **新建**，挂于 `NavAcc._pre_sim_step`；现有 `AttitudeController`/`PIDrate` 不是完整固件链 |
| Train / eval / deployment | 相同动作顺序、单位、限幅、时间步和日志 | 新增 task 注册、action spec、100 Hz inverse transform 及训练/评估入口；实机用 `send_setpoint` |

训练时环境转移由滤波后的命令产生，策略损失只用 `z_policy` 及其 log probability；CBF correction 用 `a_projected-a_nom`，名义动作平滑用 `a_nom,k-a_nom,k-1`。`r_boundary` 根据执行后的状态进入奖励，不写入 CBF 行。当前任务注册依靠导入 `NavAcc` 类，`train.py` 目前只处理 velocity/PIDrate 等旧 transform，因此新分支与评估入口都须单独接线。不得修改 NavVel 旧动作解释来复用新链。

---

## 21. 必须明确的坐标系和接口问题

本草案的公式使用世界系 `+z` 向上、推力沿机体 `+z`。真正接入 OmniDrones 和 Crazyflie 时，逐项确认 ENU/NED、机体轴、欧拉角顺序、roll/pitch/yaw 符号、角速度正方向、电机顺序与混控方向。不要把仿真中的牛顿直接传给 cflib 的整数 thrust。`send_setpoint` 的 roll/pitch 单位为度、yawrate 为度/秒；cflib 打包时对 pitch 取反，固件 legacy RPYT 路径还会对 yawrate 取反并经过后续控制符号处理。把 API 调用前的命令作为仿真与实机的共同接口，并端到端验证命令到世界系加速度的符号。固件还需确认 roll/pitch 使用 angle 模式、yaw 使用 rate 模式、位置/高度保持模式关闭，以及实际启用的控制器为 PID。

---

## 22. 速度与加速度限幅能解决什么

**第一版只对圆柱障碍构造 CBF，不加入六面 boundary 或速度 HOCBF。** 速度上限可进入名义动作范围、任务奖励/终止或监测，但不能据此宣称速度状态必然受控。物理可执行范围仍需在同一次最多 10 轮的解析投影中处理；投影后再裁剪姿态或推力会破坏已通过的障碍约束。

理想静态可行域满足 `T_min/m <= ||a+g e3|| <= T_max/m`、`a_z+g>0`、`||a_xy|| <= (a_z+g)tan(theta_max)`。完整倾角锥和偏心推力球不是当前原点球投影器的输入。为遵守**不使用 QP/Dykstra**的实现约束，第一版选一个经标定的保守内集合：

$$
\mathcal A_{inner}=\{\mathbf a:\ a_{z,min}\leq a_z\leq a_{z,max},\ \|\mathbf a_{xy}\|\leq a_{xy,max}\}.
$$

其两个闭式投影分别为 `clip(a_z, a_z_min, a_z_max)` 和 `a_xy·min(1, a_xy_max/||a_xy||)`（零向量保持零）。参数须满足 `g+a_z,min>0`、`g+a_z,min>=T_min/m`、`a_xy,max <= (g+a_z,min)tan(theta_max)`、`sqrt(a_xy,max²+(g+a_z,max)²)<=T_max/m`；这些充分条件保守，但使集合中的每个静态命令满足推力和倾角上限。参数未标定时标为 `UNVALIDATED`，只能进行明确标为探索性的仿真，不能实机部署或声称可达性。

求解器在障碍半空间与该内集合之间执行最多 10 轮闭式修正，**不调用 QP、不调用 Dykstra、不做超出 10 轮的补救迭代**。初始点已满足全部约束时可以零轮返回；否则每轮先投影到最违反的障碍半空间（若不存在障碍违例则跳过），再对 `A_inner` 作闭式投影；这一组合计为一轮。每轮及结束时检查所有原始障碍行和内集合残差。单行加集合的序列不保证全局最近点或有限轮必可行；若第 10 轮仍未通过验收，以该轮候选为最终结果，不继续迭代或清零；报告 `ITERATION_LIMIT` 和残差，不把结果当作 `a_safe`。仿真可按已验证的物理内集合执行该候选并记录碰撞/越界；实机失效处置须单独验证。课程后期最多八柱时必须统计迭代上限和未满足约束的比例。

即使静态内集合非空，姿态/电机瞬态仍会使 `a_actual` 偏离 `a_safe`。Stage 3 先用 `||a_actual-a_test/ref||` 建立跟踪误差界；Stage 4 后再核对 `||a_actual-a_safe||`，并把估计误差、采样与通信延迟纳入障碍 CBF 鲁棒裕量。当前项目的 `delta_a` 针对障碍物加速度估计，不等于本机跟踪误差界。零加速度保持当前速度，零推力也不是悬停；无效状态或饱和时不能静默使用两者代替恢复策略。

---

## 23. 阶段性验证与设计结论

修改按下列依赖顺序推进，每一阶段通过后再把下一层接入闭环：

1. **冻结接口与参数：**固定 Crazyflie 机型、固件提交/配置、质量、电机/桨、坐标系及 RPYT 模式；记录 API 到固件 yawrate、pitch、roll 的端到端符号；确认零推力同步和 `controller.yaw` 等日志信号。标定 `thrust_cmd ↔ T_actual` 的有效区间及电池补偿配置。交付命令单位/符号表和标定曲线。
2. **建立 100/500 Hz 仿真内环：**在本项目的 `IsaacEnv` 子步内运行固件兼容 yaw 参考、姿态 PID、rate PID、混控和电机模型。先固定 `HEADING_HOLD`，检查每个 2 ms 子步确实更新反馈和电机输出；用悬停、小幅水平/竖直加速度阶跃及 yaw 扰动比较仿真与实机的响应、饱和和延迟。
3. **确认加速度可达性：**此时尚未接入 C3BF，用人工阶跃/扫频 `a_test/ref` 经相同 tracker 与 RPYT 内环，记录 `a_test/ref→a_actual`、姿态、角速度、电机命令、电压和时间戳；在质量、电池状态、初始姿态及无线延迟变化下确定跟踪误差界与有效工作区。静态推力/倾角约束需与动态余量一起验证。
4. **实现加速度 C3BF：**只重推圆柱障碍碰撞锥和低速距离 HOCBF；用第 22 节的物理内集合与最多 10 轮解析修正，逐项验收可行残差、失败状态和实时耗时。六面 boundary 不进入 CBF。
5. **接入三维 Actor 与课程：**新建 NavAcc 任务，连接第 24 节的 `r_boundary`、第 25 节的五阶段柱体密度/运动速度课程、训练和评估，重新检查奖励、动作平滑、CBF 修正量及旧 checkpoint 兼容性。只有前述链路验证通过后，再启用可选 `MOTION_HEADING`。

这份草案不定义未经标定的加速度内集合、yaw 速度门限、推力映射或跟踪误差界；这些值必须来自目标机型和固件的实验记录。在这些验证完成前，该结构仍是有物理依据的**待验证架构**，不把 `a_safe` 这个变量名或一次可行的 CBF 投影等同于实机安全保证。`r_boundary` 是学习信号，不能替代硬边界安全保证。

用于 Stage 3 跟踪标定以及 Stage 4 以后 `a_actual-a_safe` 日志的加速度统一定义为同一 10 ms 外环持有窗口内的**世界系净平动平均加速度**：

$$
\mathbf a_{actual,k}=\frac{\mathbf v^W_{k+1}-\mathbf v^W_k}{\Delta t_{env}},\qquad \Delta t_{env}=0.01\,{\rm s}.
$$

`v_k^W` 与 `v_{k+1}^W` 取对应外环决策前、五个 2 ms 子步后的时间对齐状态；实机速度估计须标注采样延迟与滤波误差。这是包含外扰的净运动学平均值，不是 IMU specific force。2 ms 子步瞬时量可另存，但不能与 10 ms 持有命令混为同一跟踪误差。Stage 3 比较 `a_actual-a_test/ref`；Stage 4 以后才比较 `a_actual-a_safe`，迭代超限则比较 `a_actual-a_projected` 并保留无安全验收标志。

---

## 24. 独立边界奖励 `r_boundary`

新任务的 CBF 不构造六面 workspace 约束，奖励层单独计算 `r_boundary`；物理越界仍按任务终止逻辑处理。参考本仓 `soft_boundary_reward.py` 的方向敏感设计，但**不能直接照搬其到目标距离门控**：起点与终点都可能距边界很近，单纯按边界距离给常数惩罚会处罚合法起终点，而在目标附近把惩罚降为零又可能放任高速冲出边界。

NavAcc v1 的奖励平面与任务终止几何一致：`x=±3 m`、`y=±3 m`、`z=z_min=0.15 m`、`z=z_max=3 m`。水平 `bound_xy=5 m` 保留旧配置兼容，但在 `|x|,|y|≤3` 方盒内不会先触发，不能另造一组奖励边界。越过上/侧面按 OOB 终止，低于 `z_min` 按 crash 终止；在等号位置不终止，与当前严格不等号判定一致。对第 `i` 个面取面上一点 `p_i^plane` 与指向可飞区域的单位法向 `n_i^in`，明确定义

$$
d_i=(n_i^{in})^\top(p-p_i^{plane}),\qquad
\dot d_i=(n_i^{in})^\top v^W,\qquad
s_i=\max(0,-(n_i^{in})^\top v^W).
$$

因此 `d_i≥0` 为该面内侧，`s_i` 只惩罚朝该面外移的速度。带反应时间和估计制动距离的风险量为：

$$
q_i=d_{margin}+s_i\,t_{reaction}+\frac{s_i^2}{2a_{brake}}-d_i,\qquad
r_{boundary}=-\lambda_b\sum_{i=1}^{6}[\max(0,q_i)]^2.
$$

`a_brake`、`t_reaction`、`d_margin` 和奖励权重是**新任务待验证配置**，不是现有实机常数。 越界事件另由第 26 节的一次性 `oob=-15` 处理，不在 `r_boundary` 中重复扣罚。`d_margin` 必须小于合法起点/目标的最小静止净空，否则策略会因合法静止位置持续受罚。风险项在距墙很近但静止或朝内飞行时可为零；起点、目标附近是否为零要用实际 spawn/goal 分布检查。尤其要覆盖当前任务常见的 `x≈±2.8 m`、物理边界 `x=±3 m`、可用净空约 0.2 m 的情况；当目标也在边界附近时，允许有制动余量的朝目标运动，但应处罚预计无法在边界前停下的速度。不得为靠近目标而直接关闭边界风险项。训练与评估都记录最小面间距、外向速度、预测停止余量、`r_boundary`、实际 OOB 和到达率，防止策略学会以越界换取到达。

该奖励不能证明无人机不越界；实机部署若要求硬工作空间安全，需要独立的经验证监控/恢复机制，不能把 `r_boundary` 称作 boundary CBF。

---

## 25. 唯一的障碍场景与课程

NavAcc 仿真仅生成**静态圆柱**与**仅在 XY 平面运动的圆柱**，不生成三维球、球堆或矮柱；`cylinder_short_frac=0` 且柱体覆盖任务允许飞行的整个 z 区间。场景生成、碰撞、观测、动态跟踪和 CBF 使用同一对象 ID 与逻辑 XY 半径。静态柱 `v_obs=a_obs=0`；动态柱 `v_obs,z=a_obs,z=0`。

**动态柱真实运动模型（仿真内部）：** 每个 2 ms 物理子步选取朝当前 XY waypoint 的有界加速度 `a_obs,k`，更新

$$
\mathbf v_{obs,k+1}=\operatorname{clip}_{\|\cdot\|\le v_{obs,max}(stage)}
(\mathbf v_{obs,k}+\mathbf a_{obs,k}\Delta t_{physics}),\quad
\mathbf p_{obs,k+1}=\mathbf p_{obs,k}+\mathbf v_{obs,k+1}\Delta t_{physics},\quad
\|\mathbf a_{obs,k}\|\le a_{obs,max}(stage).
$$

`clip` 是保持方向的范数限幅。waypoint 在柱体允许活动区内；接近端点时提前按 `v²/(2a_obs,max)` 制动，速度降至零后才反向选择下一个 waypoint，不得瞬间重采速度、反号或瞬移。可借鉴现有 `nav_vel_motion.py` 的有界 `start_stop` 加减速与端点逻辑；NavAcc 的离散更新和连续往返衔接以上述契约为准。真实 `p/v/a` 只供物理和离线评估；运行时 CBF 不读取真实 `v/a`。

**`ObstacleStateEstimator` 契约（CBF 输入）：**每个柱体固定 ID 返回 `estimated_position_xy[2]`、`estimated_velocity_xy[2]`、`estimated_acceleration_xy[2]`、`radius_xy`、`sample_timestamp`、`age`、`valid`、`is_dynamic`。测量端只输入带时间戳的位置/ID/可见性；可复用现有 `obstacle_tracking.py` 的位置流与 alpha-beta 速度跟踪，但该模块当前不提供加速度估计，新任务须从连续估计速度按实际采样间隔计算并滤波，或显式采用 `a_hat=0` 且用 `a_obs,max` 覆盖误差界。静态柱固定 `v_hat=a_hat=0`；任何样本过期、ID 跳变、估计非有限或无法给出误差界时置 `valid=false`，CBF 返回失效状态。策略与 CBF 使用同一已到达时间的估计快照；仅日志和离线误差评估可访问仿真真值。

密度按以下**五阶段**在 episode reset 时切换，总容量固定为八柱，观测槽位/掩码保持固定形状：

| 阶段 | 静态柱 | 动态柱 | 总数 |
|---|---:|---:|---:|
| C0 | 0 | 1 | 1 |
| C1 | 2 | 1 | 3 |
| C2 | 2 | 2 | 4 |
| C3 | 4 | 2 | 6 |
| C4 | 4 | 4 | 8 |

障碍运动速度也使用课程：每阶段显式配置 `v_obs,max(stage)`（必要时另配 `a_obs,max(stage)`），要求 `0<v_obs,max(C0)≤...≤v_obs,max(C4)` 且末级严格高于首级；数值、运动模式和晋级阈值需由训练/评估试验确认，当前不虚构标准速度。速度等级与密度阶段一并写入 episode 元数据、checkpoint 和评估报告，**只在 reset 生效**；每次晋级前分别检查静态/动态分组的成功率、碰撞率、CBF 10 轮残差超限率、最大速度及跟踪误差。布局生成还须证明起点、目标、柱体扫掠路径和边界间有足够净空；生成失败时重采样或明确报告，不静默减少柱数。

当前本地 `DynamicCurriculum` 是 D0=2 静态、D1=2 静态+2 动态、D2=4 静态+2 动态、D3=4 静态+4 动态，且现有 speed level 不构成上述五阶段逐级提速。因此这些 C0–C4 是 **NavAcc 的新课程**，不能把旧 D0–D3 改名复用，也不得改变旧 NavVel baseline。

---

## 26. NavAcc 观测与奖励冻结契约

NavAcc v1 使用新的固定观测布局 `float32 [B,1,80]`，不复制 NavVel 的随机目标 heading 或 `rheading`。所有连续量的归一化尺度在 `NavAcc.yaml` 显式给出并在训练/评估/部署保持一致；下表先列归一化前的物理含义，顺序即网络输入顺序。

| 顺序 | 字段 | 宽度 | 原始单位/规则 |
|---|---|---:|---|
| 1 | `goal_relative_W` | 3 | 目标减本机位置，m |
| 2 | `attitude_quat_WB` | 4 | 与仿真姿态接口同序的单位四元数；顺序在新任务配置写死 |
| 3 | `velocity_W` | 3 | 本机世界系速度，m/s |
| 4 | `gyro_B` | 3 | 机体系角速度，rad/s |
| 5 | `sin(psi_hold_W),cos(psi_hold_W)` | 2 | 第一版固定 yaw 参考 |
| 6 | `episode_time_fraction` | 1 | `progress/max_episode_length` |
| 7 | 8 个固定 ID 柱槽 | `8×8=64` | 每槽如下 |

柱槽按固定对象 ID 顺序排列，每槽为 `[p_obs_xy-p_uav_xy(2 m), v_obs_xy-v_uav_xy(2 m/s), r_cyl(1 m), is_dynamic(1), age(1 s), valid(1)]`。无效/未激活槽除 `valid=0` 外其余为零；`valid` 是唯一有效性依据。策略**不接收障碍加速度真值或估计值**，加速度估计只供 CBF 与诊断。CBF 检查所有有效的八个对象，不做 nearest-K 截断；估计过期导致有效场景柱 `valid=false` 时按失效状态处理，不能把它当作不存在。固定宽度使 C0–C4 的网络结构相同。

奖励采用新建的 **`NavAcc-v1`** 配方，目标进度项沿用冻结 `f1_cbf_neutral` 的形状及 `cfg/task/profiles/NP-dual-p1-n2.yaml` 的起始权重：`reward_fly_weight=1.5`、`reward_zone_weight=1.5`、`arrive_radius=0.5 m`、`arrive_hold_steps=50`、`arrive_bonus=40`、`arrive_time_bonus=40`。即圈外 `r_fly=1.5·clip(relu(v_W·u_goal)/1.8,0,1)`，圈内改用 `r_zone=1.5+1.5(1-d_goal/0.5)`，首次连续入圈 50 个 10 ms 周期才发到达奖金；是否成功终止在 NavAcc 配置固定为 `true`。保留一次性 `collision_edge=-2`、`crash=-15`、`oob=-15`、未到达超时 `-60`，使用单命终止。`1.8 m/s` 是奖励归一化尺度，不是新控制器的速度安全保证。

在上述基础上仅增加第 24 节 `r_boundary`，并把动作平滑定义为 `r_smooth=-0.2·||S_a^{-1}(a_nom,k-a_nom,k-1)||²`；首步的上一动作在 reset 中初始化为当前首个 `a_nom`，避免无意义首步惩罚。`r_boundary` 的制动参数先由第 23 节阶跃实验给出，奖励权重在 NavAcc v1 配置中显式固定，不能继承旧 `soft_boundary_reward` 的目标距离门控。删除目标 heading 对齐、`rheading`、legacy pose/up/spin/effort 常驻奖励、PBRS、旧速度 CBF violation/correction 奖励、旧障碍 log/proximity/near-slow 奖励和动态 closing 奖励；CBF 修正量只记录诊断，不自动加到奖励。每个保留/删除项都要在训练配置中显式设置并记录配置哈希，不让入口从 NavVel 多套 reward scheme 自行选择。

---

## 27. 实施契约与验收门槛

1. **先审本地工作树：**核对本地实际代码和未提交修改；不能只看远端分支或 HEAD。新任务隔离，旧 NavVel、速度 CBF、配置、测试和 checkpoint 行为保持兼容。
2. **参数标记：**推力映射、跟踪误差界、制动能力、反应延迟、yaw 门限和课程速度未由目标机型验证时写 `UNVALIDATED`；可用明确标注的临时仿真值开发，不可据此作实机安全结论。
3. **阶段门槛：**未完成 2 ms 内环悬停/阶跃验收，不开始 PPO 训练；未测得加速度跟踪误差与延迟界，不声称鲁棒 CBF；10 轮后残差不合格，保留最后候选并标记 `valid=false`；不得把它报告为安全命令。
4. **必备证据：**每阶段提交配置、测试报告和可复核日志。至少包含 `z_policy/a_nom/a_projected/valid`、CBF 修正量、全部约束最大原始残差、选中约束和迭代数/状态、RPYT、固件 yaw 参考、姿态/rate PID 输出、motor 饱和、2 ms 子步计数、`r_boundary` 与 OOB、各课程阶段及速度级别。Stage 3 记录 `a_actual-a_test/ref`；Stage 4 后在有效投影时记录 `a_actual-a_safe`，无效投影时记录 `a_actual-a_projected` 及失败状态。可用全量统计配合抽样时序轨迹控制记录开销。

## 参考接口

- [Crazyflie 固件级联 PID 与运行频率](https://www.bitcraze.io/documentation/repository/crazyflie-firmware/master/functional-areas/sensor-to-control/controllers/)
- [Crazyflie 固件 PID 调用链](https://github.com/bitcraze/crazyflie-firmware/blob/master/src/modules/src/controller/controller_pid.c)
- [Crazyflie legacy RPYT 接收与 yawrate 符号](https://github.com/bitcraze/crazyflie-firmware/blob/master/src/modules/src/crtp_commander_rpyt.c)
- [cflib `Commander.send_setpoint`](https://github.com/bitcraze/crazyflie-lib-python/blob/master/cflib/crazyflie/commander.py)
- [cflib 低层 commander 与推力说明](https://github.com/bitcraze/crazyflie-lib-python/blob/master/docs/user-guides/python_api.md)
- [Isaac Lab 物理步长与 decimation 概念](https://isaac-sim.github.io/IsaacLab/develop/source/api/lab/isaaclab.envs.html)（仅供理解多速率语义，本仓不用该配置接口）
- 本仓代码：`OmniDrones/omni_drones/envs/isaac_env.py`、`omni_drones/utils/c3bf.py`、`safety_projection.py`、`soft_boundary_reward.py`、`dynamic_curriculum.py`、`scripts/train.py`、`scripts/eval_ckpt.py`、`cfg/task/NavVel.yaml`、`cfg/profiles/dynamic_train_base.yaml`。
