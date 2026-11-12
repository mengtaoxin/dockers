# dockers

A personal collection of Docker Compose stacks — self-contained, ready-to-run container setups for environments I use repeatedly, such as a GitHub Actions runner and Ubuntu images preconfigured with Node.js, MySQL, or Playwright browsers.

Each stack lives in its own directory and is versioned independently. When a stack is updated, its image is built automatically and published to the GitHub Container Registry (GHCR), so the same environment can be pulled and run anywhere Docker is available.
