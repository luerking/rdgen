#!/bin/bash
# ============================================================
#  跳过 secure_tcp 握手 —— 解决「登录 Console 后一直正在连接」
# ============================================================
#
#  【问题根源】
#  RustDesk 1.4.1+ 客户端在「同时持有 key 与 API 登录 token」时会发起
#  secure_tcp 加密握手（src/client.rs 两处）：
#
#      if !key.is_empty() && !token.is_empty() {
#          // mainly for the security of token
#          secure_tcp(&mut socket, &key).await ...?;
#      }
#
#  开源版 hbbs 没有 Pro 的配套应答，收到后静默不响应，
#  客户端干等到 READ_TIMEOUT（18 秒）后中止。
#  表现：报错「Failed to secure tcp: deadline has elapsed」，
#        或界面一直卡「正在连接」。
#
#  不登录账号 → token 为空 → 不触发握手 → 所以「不登录反而能用」。
#
#  【本脚本做法】
#  把两个调用点的判定条件改成 `if false && ...`，让握手永不执行，
#  客户端直接进入正常的 rendezvous 消息交换。
#
#  【代价】
#  token 不再通过该握手加密保护。流量仍走你自己的 hbbs/hbbr，
#  仅失去 token 在链路上的额外保密性。自建场景可接受。
#
#  【为什么不用 patch 文件】
#  靠代码特征（而非行号）匹配，跨 RustDesk 版本更耐漂移。
#  sed -i 在 GitHub Windows runner 的 Git Bash 上可用。
# ============================================================

CLIENT_RS="./src/client.rs"

if [ ! -f "$CLIENT_RS" ]; then
  echo "错误：未找到 $CLIENT_RS"
  echo "请确认该步骤位于「Checkout source code」之后"
  exit 1
fi

# 先记录原始状态，便于日志里核对
echo "=== 打补丁前 ==="
grep -n 'if !key.is_empty() && !token.is_empty() {' "$CLIENT_RS" || echo "（未找到目标代码）"

# 精确替换：把 if 条件加上 `false &&` 前缀
sed -i 's/if !key\.is_empty() && !token\.is_empty() {/if false \&\& !key.is_empty() \&\& !token.is_empty() {/g' "$CLIENT_RS"

echo "=== 打补丁后 ==="
grep -n 'if false && !key.is_empty() && !token.is_empty() {' "$CLIENT_RS" || echo "（替换失败）"

# 校验：必须命中 2 处（_start_inner 与 request_relay 各一处）
HITS=$(grep -c 'if false && !key.is_empty() && !token.is_empty() {' "$CLIENT_RS" || true)
echo "命中数量: $HITS"

if [ "$HITS" -eq 2 ]; then
  echo "✅ 补丁成功：2 处调用点已禁用握手"
else
  echo "❌ 补丁异常：预期 2 处，实际 $HITS 处"
  echo "   可能该 RustDesk 版本结构已变化，请检查 src/client.rs"
  exit 1
fi