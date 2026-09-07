# Docker Image Optimization: From 1.2 GB to 10 MB

Structured notes from transcript. Example uses a Node + React app, but the tips apply to all Docker images (Python, etc.).

## Why Every Megabyte Counts

Smaller images improve:

- Storage cost
- Deployment times
- Scalability
- Security (smaller attack surface)

Impact is amplified with orchestrators like Kubernetes.

Progress in the transcript:

| Step | Technique | Approx. Size |
| --- | --- | --- |
| 0 | `node:latest` baseline | ~1.2 GB |
| 1 | `node:alpine` base image | ~250 MB (~80% reduction) |
| 2 | Layer caching (no size change, faster rebuilds) | ~250 MB |
| 3 | `.dockerignore` (smaller build context, faster builds) | ~250 MB |
| 4 | Single `RUN` cleanup | smaller, but app broken in example |
| 5 | Multi-stage build + nginx | ~57 MB |
| 6 | Slim / DockerSlim `slim build` | ~10 MB |

## 1. Choose a Minimal Base Image

Problem:

```dockerfile
FROM node:latest
```

`node:latest` is over 1 GB. Same for full `python` images. Transcript analogy: using a cargo ship to deliver a letter.

Fix: append `-alpine`:

```dockerfile
FROM node:alpine
```

Result in transcript: 1.2 GB -> ~250 MB with ~7 extra characters.

Why it works:

- Alpine is purpose-built for containers.
- Strips everything except bare essentials to run your application.

Caveats:

- Alpine uses different system libraries (musl vs glibc in standard Linux distros).
- Can cause compatibility issues, especially with native modules.
- With most popular images you can find a variant more minimal than the default.
- Practical workflow: use full image for development, figure out what is needed, use minimal image for production.

Note on Distroless:

- Google Distroless images contain no OS at all: no shell, no package manager, not even basic Linux commands.
- Just your application and its runtime.
- More complex to set up. Transcript sticks to Alpine, but links Distroless as further reading.

## 2. Use Layer Caching for Speed

Problem: changing one line of React code triggers full rebuild and reinstall of all dependencies with `docker build`.

Background:

- Each instruction in a Dockerfile creates a new layer.
- Docker reuses layers that have not changed from a previous build.

Bad pattern: copy all source, then install:

```dockerfile
COPY . .
RUN npm install
RUN npm run build
```

Any code change invalidates the dependency layer.

Better pattern: copy dependency manifest first:

```dockerfile
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build
```

Now rebuild after a code change reuses the cached dependency layer and only rebuilds the code layer.

Same idea for Python:

```dockerfile
COPY requirements.txt ./
RUN pip install -r requirements.txt
COPY . .
```

Cache invalidation triggers:

1. Changes to the file being copied.
2. Changes to the Dockerfile instruction itself.
3. Changes to any previous layer.

Rule: order matters. Put most stable layers at the top, most frequently changing layers at the bottom.

## 3. Remove Unneeded Files with `.dockerignore`

Problem: running `npm install` locally, then `COPY . .` sends a lot of useless context, e.g. local `node_modules`. `docker build` output shows how much context was transferred.

It is useless because the image reinstalls modules itself.

Fix: add a `.dockerignore`:

```dockerignore
node_modules
.git
*.log
.env
```

Also exclude secrets — they should never go into the build context/image.

Result: much less build context transferred. Speeds up builds significantly, especially for larger apps.

## 4. Understand Layers: Combine Cleanup in One `RUN`

After building, the container may contain files not needed at runtime. Example: if the React app is already built to static files, `node_modules` may not be needed for preview/production serving.

Naive cleanup does not work:

```dockerfile
RUN npm install
RUN npm run build
RUN rm -rf node_modules
RUN rm -rf /tmp/* ~/.cache
```

Still same large image. Reason:

- Each Docker layer is immutable and contains only the changes from the previous layer.
- Separate `RUN` delete in a later layer only marks files as inaccessible in the final container, but files still exist in earlier layers and still consume image space.

Fixed version — one `RUN`:

```dockerfile
RUN npm install \
  && npm run build \
  && rm -rf node_modules /tmp/* ~/.cache
```

Now all operations happen in a single layer. The committed layer contains only the final state, not the intermediate state with extra files.

Security implication:

- Do not `COPY .env` / secrets then `RUN rm` them on another line.
- They remain findable/extractable from earlier layers.
- Never copy secrets into the image in the first place; use build secrets / runtime env / `.dockerignore`.

Note: in the transcript example, deleting `node_modules` alone breaks the app because it relied on a Node preview server to host static HTML. The solution is multi-stage builds + a static server.

## 5. Multi-Stage Builds — The Biggest Win

After build, only needed artifacts are:

- `dist/` / `build/` static files (HTML/CSS/JS in example)
- A way to serve them

No need for Node, npm, `node_modules`, or source code in the final container.

```dockerfile
# Stage 1: builder
FROM node:alpine AS builder
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

# Stage 2: runtime
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
```

Key points:

- `FROM ... AS builder` then second `FROM nginx` separates stages.
- Everything in builder stage (Node, npm, `node_modules`, source) is thrown away.
- Final image only has built assets + very small nginx image.

Result in transcript: down to ~57 MB.

## 6. Analysis and Minification Tools

Dockerfiles get complex. Two tools from transcript:

### Dive

- Image explorer.
- Inspect individual layers.
- Find ways to optimize and debug builds.

Typical use:

```bash
dive <image>:<tag>
```

### Slim (DockerSlim)

- Inspect, optimize, and debug containers.
- No changes needed to the container image itself.
- Claims up to ~30x minification while making it more secure.
- Extras: `xray` and linting to understand and author better images.

Typical use from transcript:

```bash
slim build <image>:<tag>
```

Transcript result after `slim build` on the already-optimized image: final ~10 MB.

## Dockerfile Best Practices Checklist

1. Start minimal: `*-alpine` / `*-slim` / distroless for production.
2. Order layers stable -> volatile for cache reuse.
3. Copy `package.json` / `requirements.txt` first, install, then copy code.
4. Always add `.dockerignore` (`node_modules`, `.git`, logs, `.env`).
5. Never `COPY` secrets; clean caches in the same `RUN`.
6. Combine related `RUN` cleanup into a single layer.
7. Use multi-stage builds; copy only runtime artifacts to final stage.
8. Serve static output with minimal runtime (`nginx:alpine`, distroless).
9. Inspect with `dive`, minify/audit with `slim`.

## Source

Transcript: Docker 1.2 GB -> 10 MB walkthrough with Node/React example. Typos cleaned: `drist` -> Distroless, `Eng Jinx` -> nginx, `mpm` -> npm.
