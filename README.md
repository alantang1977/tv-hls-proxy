````markdown
# TV HLS Proxy Docker 部署说明

## 环境要求

支持：

- x86-64
- ARM64

需要：

- Docker >= 20.10
- Docker Compose（可选）

---

## 1. 拉取镜像

指定版本：

```bash
docker pull wjecee/tv-hls-proxy:sha-28e9c28
````

使用最新版：

```bash
docker pull wjecee/tv-hls-proxy:latest
```

---

## 2. 创建并运行容器

```bash
docker run -d \
  --name cctv-service \
  --shm-size=64m \
  --memory=600m \
  --restart=unless-stopped \
  -p 3000:3000 \
  wjecee/tv-hls-proxy:sha-28e9c28
```

参数说明：

| 参数                         | 说明              |
| -------------------------- | --------------- |
| `--name cctv-service`      | 容器名称            |
| `--shm-size=64m`           | Chromium 共享内存限制 |
| `--memory=600m`            | 容器最大内存限制        |
| `--restart=unless-stopped` | 自动重启            |
| `-p 3000:3000`             | 映射 HTTP 服务端口    |

---

## 3. 查看运行状态

```bash
docker ps
```

正常：

```
CONTAINER ID   IMAGE                          STATUS
xxxx           wjecee/tv-hls-proxy           Up
```

---

## 4. 查看日志

实时日志：

```bash
docker logs -f cctv-service
```

最近日志：

```bash
docker logs --tail=100 cctv-service
```

---

## 5. 测试服务

浏览器访问：

```
http://服务器IP:3000
```

或者：

```bash
curl http://127.0.0.1:3000
```

---

## 6. 更新镜像

停止旧容器：

```bash
docker stop cctv-service
```

删除：

```bash
docker rm cctv-service
```

拉取最新镜像：

```bash
docker pull wjecee/tv-hls-proxy:latest
```

重新启动：

```bash
docker run -d \
  --name cctv-service \
  --shm-size=64m \
  --memory=600m \
  --restart=unless-stopped \
  -p 3000:3000 \
  wjecee/tv-hls-proxy:latest
```

---

## 7. 查看资源占用

```bash
docker stats cctv-service
```

示例：

```
NAME             CPU %     MEM USAGE
cctv-service     2%        300MiB / 600MiB
```

导出 live.m3u,ip修改为你部署的机器的ip
```
curl http://192.168.1.1:3000/live.m3u -o live.m3u
```
---

## 8. 停止服务

停止：

```bash
docker stop cctv-service
```

启动：

```bash
docker start cctv-service
```

删除：

```bash
docker rm -f cctv-service
```

---

## 9. 多架构支持

该镜像包含：

```
linux/amd64
linux/arm64
```

Docker 会根据宿主机架构自动选择对应镜像：

x86-64:

```
linux/amd64
```

ARM64:

```
linux/arm64
```

无需手动指定架构。

````
