下面统一使用：

* \(p_{\mathrm{rel},i}\)：第 \(i\) 个障碍物相对无人机的位置；
* \(v_{\mathrm{rel},i}\)：第 \(i\) 个障碍物相对无人机的速度；
* \(a_{\mathrm{obs},i}\)：障碍物加速度；
* \(u\)：发送给四旋翼速度环的速度指令。

这样不再使用 \(a_i\)、\(w_i\) 表示相对位置和相对速度，避免与线加速度 \(a\) 和角速度 \(\omega\) 混淆。

---

## 1. 四旋翼速度环模型

采用一阶速度环近似：

$$
\dot p = v
$$

$$
\dot v = \frac{u-v}{\tau}
$$

其中：

* \(p\in\mathbb R^3\)：四旋翼位置；
* \(v\in\mathbb R^3\)：四旋翼实际速度；
* \(u\in\mathbb R^3\)：速度指令；
* \(\tau>0\)：速度环时间常数。

对于第 \(i\) 个障碍物，位置、速度、加速度分别记为

$$
p_{\mathrm{obs},i},
\qquad
v_{\mathrm{obs},i},
\qquad
a_{\mathrm{obs},i}.
$$

定义相对位置：

$$
p_{\mathrm{rel},i}
=
p_{\mathrm{obs},i}-p
$$

定义相对速度：

$$
v_{\mathrm{rel},i}
=
v_{\mathrm{obs},i}-v
$$

因此有

$$
\dot p_{\mathrm{rel},i}
=
v_{\mathrm{rel},i}.
$$

又因为

$$
\dot v_{\mathrm{obs},i}
=
a_{\mathrm{obs},i},
$$

所以

$$
\dot v_{\mathrm{rel},i}
=
a_{\mathrm{obs},i}
-
\frac{u-v}{\tau}.
$$

即

$$
\dot v_{\mathrm{rel},i}
=
a_{\mathrm{obs},i}
+
\frac{v-u}{\tau}.
$$

对于静态障碍物：

$$
v_{\mathrm{obs},i}=0,
\qquad
a_{\mathrm{obs},i}=0.
$$

对于匀速动态障碍物：

$$
v_{\mathrm{obs},i}\neq0,
\qquad
a_{\mathrm{obs},i}=0.
$$

因此静态和动态障碍可以使用完全相同的 CBF 计算流程。

---

## 2. 碰撞锥 CBF

把四旋翼自身尺寸、障碍物尺寸和安全裕度统一到碰撞半径：

$$
R_i
=
r_{\mathrm{uav}}
+
r_{\mathrm{obs},i}
+
r_{\mathrm{margin}}.
$$

定义相对距离：

$$
d_i
=
\left\|p_{\mathrm{rel},i}\right\|.
$$

要求：

$$
d_i>R_i.
$$

定义碰撞锥几何量：

$$
\rho_i
=
\sqrt{
\left\|p_{\mathrm{rel},i}\right\|^2
-
R_i^2
}.
$$

C3BF 取为：

$$
h_i
=
p_{\mathrm{rel},i}^{T}v_{\mathrm{rel},i}
+
\rho_i
\left\|v_{\mathrm{rel},i}\right\|.
$$

安全集合为：

$$
h_i\ge0.
$$

这仍然是 collision-cone CBF 的原始几何含义：相对速度不能进入碰撞锥内部。

---

## 3. 对 CBF 求导

为了简化符号，下面暂时省略障碍物下标 \(i\)。

写成：

$$
h
=
p_{\mathrm{rel}}^{T}v_{\mathrm{rel}}
+
\rho
\left\|v_{\mathrm{rel}}\right\|
$$

其中

$$
\rho
=
\sqrt{
p_{\mathrm{rel}}^{T}p_{\mathrm{rel}}
-
R^2
}.
$$

首先：

$$
\frac{\partial \rho}
{\partial p_{\mathrm{rel}}}
=
\frac{p_{\mathrm{rel}}}{\rho}.
$$

因此：

$$
\frac{\partial h}
{\partial p_{\mathrm{rel}}}
=
v_{\mathrm{rel}}
+
\frac{
\left\|v_{\mathrm{rel}}\right\|
}{
\rho
}
p_{\mathrm{rel}}.
$$

定义：

$$
s
=
v_{\mathrm{rel}}
+
\frac{
\left\|v_{\mathrm{rel}}\right\|
}{
\rho
}
p_{\mathrm{rel}}.
$$

另一方面：

$$
\frac{\partial h}
{\partial v_{\mathrm{rel}}}
=
p_{\mathrm{rel}}
+
\rho
\frac{
v_{\mathrm{rel}}
}{
\left\|v_{\mathrm{rel}}\right\|
}.
$$

定义：

$$
q
=
p_{\mathrm{rel}}
+
\rho
\frac{
v_{\mathrm{rel}}
}{
\left\|v_{\mathrm{rel}}\right\|
}.
$$

其中 \(q\in\mathbb R^3\) 是后面解析投影最关键的向量。

---

## 4. 一阶速度环下的 CBF 导数

利用：

$$
\dot p_{\mathrm{rel}}
=
v_{\mathrm{rel}}
$$

以及：

$$
\dot v_{\mathrm{rel}}
=
a_{\mathrm{obs}}
+
\frac{v-u}{\tau},
$$

有：

$$
\dot h
=
\left(
\frac{\partial h}
{\partial p_{\mathrm{rel}}}
\right)^T
\dot p_{\mathrm{rel}}
+
\left(
\frac{\partial h}
{\partial v_{\mathrm{rel}}}
\right)^T
\dot v_{\mathrm{rel}}.
$$

代入：

$$
\dot h
=
s^T v_{\mathrm{rel}}
+
q^T
\left(
a_{\mathrm{obs}}
+
\frac{v-u}{\tau}
\right).
$$

其中：

$$
s^T v_{\mathrm{rel}}
=
\left(
v_{\mathrm{rel}}
+
\frac{
\left\|v_{\mathrm{rel}}\right\|
}{
\rho
}
p_{\mathrm{rel}}
\right)^T
v_{\mathrm{rel}}.
$$

所以：

$$
s^T v_{\mathrm{rel}}
=
\left\|v_{\mathrm{rel}}\right\|^2
+
\frac{
\left\|v_{\mathrm{rel}}\right\|
}{
\rho
}
p_{\mathrm{rel}}^T v_{\mathrm{rel}}.
$$

最终：

$$
\dot h
=
\left\|v_{\mathrm{rel}}\right\|^2
+
\frac{
\left\|v_{\mathrm{rel}}\right\|
}{
\rho
}
p_{\mathrm{rel}}^T v_{\mathrm{rel}}
+
q^T a_{\mathrm{obs}}
+
\frac{1}{\tau}q^T v
-
\frac{1}{\tau}q^T u.
$$

---

# 5. CBF 转换成速度指令的线性半空间

采用 exponential CBF 条件：

$$
\dot h+\gamma h\ge0
$$

其中：

$$
\gamma>0.
$$

将上式代入：

$$
\left\|v_{\mathrm{rel}}\right\|^2
+
\frac{
\left\|v_{\mathrm{rel}}\right\|
}{
\rho
}
p_{\mathrm{rel}}^T v_{\mathrm{rel}}
+
q^T a_{\mathrm{obs}}
+
\frac{1}{\tau}q^T v
-
\frac{1}{\tau}q^T u
+
\gamma h
\ge0.
$$

两边乘以 \(\tau\)：

$$
\tau
\left\|v_{\mathrm{rel}}\right\|^2
+
\tau
\frac{
\left\|v_{\mathrm{rel}}\right\|
}{
\rho
}
p_{\mathrm{rel}}^T v_{\mathrm{rel}}
+
\tau q^T a_{\mathrm{obs}}
+
q^T v
-
q^T u
+
\tau\gamma h
\ge0.
$$

整理关于 \(u\) 的项，得到：

$$
q^T u
\le
b.
$$

其中：

$$
b
=
q^T v
+
\tau
\left[
\left\|v_{\mathrm{rel}}\right\|^2
+
\frac{
\left\|v_{\mathrm{rel}}\right\|
}{
\rho
}
p_{\mathrm{rel}}^T v_{\mathrm{rel}}
+
q^T a_{\mathrm{obs}}
+
\gamma h
\right].
$$

因此，对于第 \(i\) 个障碍物：

$$
q_i^T u
\le
b_i.
$$

这里：

$$
q_i
=
p_{\mathrm{rel},i}
+
\rho_i
\frac{
v_{\mathrm{rel},i}
}{
\left\|v_{\mathrm{rel},i}\right\|
}.
$$

以及：

$$
b_i
=
q_i^T v
+
\tau
\left[
\left\|v_{\mathrm{rel},i}\right\|^2
+
\frac{
\left\|v_{\mathrm{rel},i}\right\|
}{
\rho_i
}
p_{\mathrm{rel},i}^T
v_{\mathrm{rel},i}
+
q_i^T a_{\mathrm{obs},i}
+
\gamma_i h_i
\right].
$$

---

# 6. 如果假设障碍物匀速

对于大多数第一版实现，可以直接假设：

$$
a_{\mathrm{obs},i}=0.
$$

那么：

$$
b_i
=
q_i^T v
+
\tau
\left[
\left\|v_{\mathrm{rel},i}\right\|^2
+
\frac{
\left\|v_{\mathrm{rel},i}\right\|
}{
\rho_i
}
p_{\mathrm{rel},i}^T
v_{\mathrm{rel},i}
+
\gamma_i h_i
\right].
$$

此时每一个障碍物都只产生一个线性约束：

$$
q_i^T u\le b_i.
$$

这就是后面做解析投影所需要的全部信息。

---

# 7. 单障碍的解析投影

设 nominal controller 输出：

$$
u_{\mathrm{des}}.
$$

希望寻找和它最接近的安全速度指令：

$$
\min_u
\frac{1}{2}
\left\|
u-u_{\mathrm{des}}
\right\|^2
$$

满足：

$$
q^T u\le b.
$$

如果：

$$
q^T u_{\mathrm{des}}\le b,
$$

说明原始速度指令已经安全，因此：

$$
u^\star=u_{\mathrm{des}}.
$$

如果：

$$
q^T u_{\mathrm{des}}>b,
$$

则将 \(u_{\mathrm{des}}\) 正交投影到平面

$$
q^T u=b
$$

上。

解析解为：

$$
u^\star
=
u_{\mathrm{des}}
-
\frac{
q^T u_{\mathrm{des}}-b
}{
q^Tq
}
q.
$$

因此可以统一写成：

$$
u^\star
=
u_{\mathrm{des}}
-
\max
\left(
0,
\frac{
q^T u_{\mathrm{des}}-b
}{
q^Tq
}
\right)
q.
$$

这就是单障碍情况下完整的解析 CBF safety filter。

---

# 8. 单障碍实现代码

```python
import numpy as np


def c3bf_velocity_projection(
    p,
    v,
    u_des,
    p_obs,
    v_obs,
    collision_radius,
    tau,
    gamma,
    a_obs=None,
    eps_v=1e-3,
    eps_rho=1e-4,
):
    """
    Analytical C3BF velocity projection.

    Parameters
    ----------
    p : ndarray, shape (3,)
        UAV position.

    v : ndarray, shape (3,)
        UAV actual velocity.

    u_des : ndarray, shape (3,)
        Nominal velocity command.

    p_obs : ndarray, shape (3,)
        Obstacle position.

    v_obs : ndarray, shape (3,)
        Obstacle velocity.

    collision_radius : float
        Inflated collision radius.

    tau : float
        First-order velocity-loop time constant.

    gamma : float
        CBF gain.

    a_obs : ndarray, shape (3,), optional
        Obstacle acceleration.
    """

    if a_obs is None:
        a_obs = np.zeros(3)

    # Relative states
    p_rel = p_obs - p
    v_rel = v_obs - v

    distance_sq = np.dot(p_rel, p_rel)
    R = collision_radius

    if distance_sq <= R * R:
        raise RuntimeError(
            "UAV is already inside the inflated collision region."
        )

    # Collision cone geometry
    rho = np.sqrt(
        max(distance_sq - R * R, eps_rho**2)
    )

    # Smooth relative-speed norm
    v_rel_norm = np.sqrt(
        np.dot(v_rel, v_rel) + eps_v**2
    )

    # C3BF
    h = (
        np.dot(p_rel, v_rel)
        + rho * v_rel_norm
    )

    # dh / d(v_rel)
    q = (
        p_rel
        + rho * v_rel / v_rel_norm
    )

    # Drift part of dh/dt
    drift = (
        np.dot(v_rel, v_rel)
        + (v_rel_norm / rho)
        * np.dot(p_rel, v_rel)
        + np.dot(q, a_obs)
    )

    # Half-space:
    #
    # q^T u <= b
    #
    b = (
        np.dot(q, v)
        + tau * (drift + gamma * h)
    )

    violation = np.dot(q, u_des) - b

    # Already feasible
    if violation <= 0.0:
        return u_des.copy(), h, False

    q_norm_sq = np.dot(q, q)

    if q_norm_sq < 1e-10:
        return u_des.copy(), h, False

    # Analytical Euclidean projection
    u_safe = (
        u_des
        - violation / q_norm_sq * q
    )

    return u_safe, h, True
```

静态障碍物：

```python
v_obs = np.zeros(3)
a_obs = np.zeros(3)
```

匀速动态障碍物：

```python
v_obs = estimated_obstacle_velocity
a_obs = np.zeros(3)
```

如果有可靠的障碍物加速度估计：

```python
v_obs = estimated_obstacle_velocity
a_obs = estimated_obstacle_acceleration
```

---

# 9. 多障碍的统一表示

对于 \(N\) 个障碍物，每一个障碍产生：

$$
q_i^T u\le b_i.
$$

把它们堆起来：

$$
Au\le b
$$

其中：

$$
A
=
\begin{bmatrix}
q_1^T\\
q_2^T\\
\vdots\\
q_N^T
\end{bmatrix}
$$

以及：

$$
b
=
\begin{bmatrix}
b_1\\
b_2\\
\vdots\\
b_N
\end{bmatrix}.
$$

最终问题为：

$$
\min_u
\frac12
\left\|
u-u_{\mathrm{des}}
\right\|^2
$$

满足：

$$
Au\le b.
$$

因为：

$$
u\in\mathbb R^3,
$$

所以在非退化情况下，最优点最多需要三个线性独立的 active constraints。

---

# 10. 多障碍 active-set 的解析解

假设某个候选 active set 为 \(S\)。

对应矩阵：

$$
A_S
$$

和：

$$
b_S.
$$

active constraint 满足：

$$
A_Su=b_S.
$$

相应投影问题：

$$
\min_u
\frac12
\left\|
u-u_{\mathrm{des}}
\right\|^2
$$

满足：

$$
A_Su=b_S.
$$

解析解为：

$$
u_S
=
u_{\mathrm{des}}
-
A_S^T
\left(
A_SA_S^T
\right)^{-1}
\left(
A_Su_{\mathrm{des}}-b_S
\right).
$$

对应 KKT 乘子：

$$
\lambda_S
=
\left(
A_SA_S^T
\right)^{-1}
\left(
A_Su_{\mathrm{des}}-b_S
\right).
$$

合法候选必须满足：

$$
\lambda_S\ge0
$$

以及：

$$
Au_S\le b.
$$

然后在所有合法候选中选择：

$$
\left\|
u_S-u_{\mathrm{des}}
\right\|^2
$$

最小的那个。

---

# 11. 三维情况下的 active-set 枚举

由于控制变量只有：

$$
u=
\begin{bmatrix}
u_x\\
u_y\\
u_z
\end{bmatrix},
$$

所以只需要枚举：

$$
|S|=1,
$$

$$
|S|=2,
$$

和：

$$
|S|=3.
$$

算法可以写成：

```text
if u_des satisfies all constraints:
    return u_des

candidates = []

enumerate every active set containing 1 constraint
    compute analytical projection
    check KKT
    check all CBF constraints

enumerate every active set containing 2 constraints
    compute analytical projection
    check KKT
    check all CBF constraints

enumerate every active set containing 3 constraints
    compute analytical projection
    check KKT
    check all CBF constraints

return feasible candidate with minimum
||u - u_des||^2
```

对应 Python：

```python
import itertools
import numpy as np


def project_halfspaces_3d(
    u_des,
    A,
    b,
    tol=1e-8,
):
    u_des = np.asarray(u_des, dtype=float)
    A = np.asarray(A, dtype=float)
    b = np.asarray(b, dtype=float)

    num_constraints = len(b)

    # u_des already feasible
    if np.all(A @ u_des <= b + tol):
        return u_des.copy(), True

    candidates = []

    max_active = min(3, num_constraints)

    for num_active in range(1, max_active + 1):

        for active_ids in itertools.combinations(
            range(num_constraints),
            num_active,
        ):
            A_active = A[list(active_ids)]
            b_active = b[list(active_ids)]

            G = A_active @ A_active.T

            if np.linalg.matrix_rank(G) < num_active:
                continue

            rhs = (
                A_active @ u_des
                - b_active
            )

            try:
                lam = np.linalg.solve(G, rhs)
            except np.linalg.LinAlgError:
                continue

            # KKT multipliers
            if np.any(lam < -tol):
                continue

            u_candidate = (
                u_des
                - A_active.T @ lam
            )

            # Check every CBF constraint
            if np.all(
                A @ u_candidate <= b + tol
            ):
                cost = np.dot(
                    u_candidate - u_des,
                    u_candidate - u_des,
                )

                candidates.append(
                    (cost, u_candidate)
                )

    if not candidates:
        return None, False

    candidates.sort(
        key=lambda item: item[0]
    )

    return candidates[0][1], True
```

---

# 12. 建议单独写一个 CBF 约束生成函数

工程实现中，最好把：

> “计算 C3BF”

和：

> “解析投影”

彻底分离。

CBF 只负责输出：

$$
q_i,
\qquad
b_i,
\qquad
h_i.
$$

例如：

```python
def build_c3bf_constraint(
    p,
    v,
    p_obs,
    v_obs,
    collision_radius,
    tau,
    gamma,
    a_obs=None,
    eps_v=1e-3,
    eps_rho=1e-4,
):
    if a_obs is None:
        a_obs = np.zeros(3)

    p_rel = p_obs - p
    v_rel = v_obs - v

    distance_sq = np.dot(
        p_rel,
        p_rel,
    )

    R = collision_radius

    if distance_sq <= R * R:
        return None, None, None

    rho = np.sqrt(
        max(
            distance_sq - R * R,
            eps_rho**2,
        )
    )

    v_rel_norm = np.sqrt(
        np.dot(v_rel, v_rel)
        + eps_v**2
    )

    h = (
        np.dot(p_rel, v_rel)
        + rho * v_rel_norm
    )

    q = (
        p_rel
        + rho
        * v_rel
        / v_rel_norm
    )

    drift = (
        np.dot(v_rel, v_rel)
        + v_rel_norm
        / rho
        * np.dot(p_rel, v_rel)
        + np.dot(q, a_obs)
    )

    b = (
        np.dot(q, v)
        + tau
        * (drift + gamma * h)
    )

    return q, b, h
```

然后多障碍：

```python
A = []
b = []

for obs in obstacles:

    q_i, b_i, h_i = build_c3bf_constraint(
        p=p,
        v=v,
        p_obs=obs.position,
        v_obs=obs.velocity,
        collision_radius=(
            uav_radius
            + obs.radius
            + safety_margin
        ),
        tau=tau,
        gamma=gamma,
    )

    if q_i is None:
        # Already inside inflated obstacle region.
        emergency = True
        continue

    A.append(q_i)
    b.append(b_i)

A = np.asarray(A)
b = np.asarray(b)

u_safe, feasible = project_halfspaces_3d(
    u_des,
    A,
    b,
)
```

---

# 13. 数值实现中的两个特殊情况

### 相对速度接近零

原始公式存在：

$$
\frac{
v_{\mathrm{rel}}
}{
\left\|v_{\mathrm{rel}}\right\|
}.
$$

当：

$$
v_{\mathrm{rel}}=0
$$

时不可导。文档也指出 \(v_{\mathrm{rel}}=0\) 是 C3BF 需要额外处理的不可微面。

实现中可以采用平滑范数：

$$
\left\|v_{\mathrm{rel}}\right\|_{\epsilon}
=
\sqrt{
v_{\mathrm{rel}}^Tv_{\mathrm{rel}}
+
\epsilon_v^2
}.
$$

然后用：

$$
\frac{
v_{\mathrm{rel}}
}{
\left\|v_{\mathrm{rel}}\right\|_{\epsilon}
}.
$$

### 接近碰撞半径

当：

$$
\left\|p_{\mathrm{rel}}\right\|
\rightarrow R^+
$$

时：

$$
\rho
=
\sqrt{
\left\|p_{\mathrm{rel}}\right\|^2-R^2
}
\rightarrow0.
$$

而公式存在：

$$
\frac{1}{\rho}.
$$

因此实际实现应至少设置：

$$
\rho
\ge
\rho_{\min}.
$$

更推荐通过安全膨胀半径，使正常 CBF 工作区域不要真的进入 \(\rho\approx0\) 的数值奇异区。

---

# 14. 最终可以压缩成这组核心公式

系统：

$$
\dot p=v
$$

$$
\dot v=\frac{u-v}{\tau}.
$$

第 \(i\) 个障碍物：

$$
p_{\mathrm{rel},i}
=
p_{\mathrm{obs},i}-p
$$

$$
v_{\mathrm{rel},i}
=
v_{\mathrm{obs},i}-v.
$$

碰撞锥：

$$
\rho_i
=
\sqrt{
\left\|p_{\mathrm{rel},i}\right\|^2
-
R_i^2
}.
$$

CBF：

$$
h_i
=
p_{\mathrm{rel},i}^{T}
v_{\mathrm{rel},i}
+
\rho_i
\left\|v_{\mathrm{rel},i}\right\|.
$$

定义：

$$
q_i
=
p_{\mathrm{rel},i}
+
\rho_i
\frac{
v_{\mathrm{rel},i}
}{
\left\|v_{\mathrm{rel},i}\right\|
}.
$$

若障碍物采用匀速模型：

$$
a_{\mathrm{obs},i}=0,
$$

则：

$$
b_i
=
q_i^Tv
+
\tau
\left[
\left\|v_{\mathrm{rel},i}\right\|^2
+
\frac{
\left\|v_{\mathrm{rel},i}\right\|
}{
\rho_i
}
p_{\mathrm{rel},i}^{T}
v_{\mathrm{rel},i}
+
\gamma_i h_i
\right].
$$

CBF 约束：

$$
\boxed{
q_i^T u\le b_i
}
$$

单障碍解析投影：

$$
\boxed{
u^\star
=
u_{\mathrm{des}}
-
\max
\left(
0,
\frac{
q_i^Tu_{\mathrm{des}}-b_i
}{
q_i^Tq_i
}
\right)
q_i
}
$$

这组符号比较适合后续直接写进论文或代码：\(p_{\mathrm{rel}}\) 和 \(v_{\mathrm{rel}}\) 始终代表相对状态，\(a_{\mathrm{obs}}\) 专门表示障碍物加速度，而 \(\omega\) 可以继续保留给四旋翼角速度，不会产生符号冲突。
