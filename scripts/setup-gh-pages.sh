#!/bin/bash
# Setup gh-pages branch for Helm repository
set -e

echo "Setting up gh-pages branch for Helm repository..."

# Check if gh-pages branch exists
if git show-ref --verify --quiet refs/heads/gh-pages; then
    echo "gh-pages branch already exists"
    exit 0
fi

# Create orphan branch
git checkout --orphan gh-pages

# Remove all files
git rm -rf .

# Create initial index.html
cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>FreeRADIUS Helm Repository</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #333; }
        pre { background: #f4f4f4; padding: 15px; border-radius: 5px; overflow-x: auto; }
        code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>FreeRADIUS Helm Repository</h1>
    <p>This is a Helm chart repository for FreeRADIUS.</p>

    <h2>Usage</h2>
    <pre>
# Add repository
helm repo add freeradius https://YOUR_USERNAME.github.io/freeradius-stack
helm repo update

# Install
helm install freeradius freeradius/freeradius \
    --namespace freeradius \
    --create-namespace
    </pre>

    <h2>Available Charts</h2>
    <ul>
        <li><code>freeradius/freeradius</code> - FreeRADIUS with MySQL backend</li>
    </ul>

    <p>For more information, see the <a href="https://github.com/YOUR_USERNAME/freeradius-stack">GitHub repository</a>.</p>
</body>
</html>
EOF

# Create empty index.yaml (will be populated by Helm)
echo "apiVersion: v1
entries: {}
generated: \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" > index.yaml

# Commit
git add index.html index.yaml
git commit -m "Initialize Helm repository"

echo ""
echo "gh-pages branch created!"
echo ""
echo "Next steps:"
echo "1. Push the branch: git push -u origin gh-pages"
echo "2. Enable GitHub Pages in repository settings (Source: gh-pages branch)"
echo "3. Switch back to main: git checkout main"
