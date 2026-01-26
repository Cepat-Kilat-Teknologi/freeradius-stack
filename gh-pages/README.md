# gh-pages Branch Content

This folder contains the files for the `gh-pages` branch (Helm repository).

## How to Create gh-pages Branch

```bash
# 1. Create orphan branch
git checkout --orphan gh-pages

# 2. Remove all files
git rm -rf .

# 3. Copy files from this folder
cp -r gh-pages/* .
rm -rf gh-pages

# 4. Commit and push
git add index.html index.yaml
git commit -m "Initialize Helm repository"
git push -u origin gh-pages

# 5. Switch back to main
git checkout main
```

## Enable GitHub Pages

1. Go to repository Settings → Pages
2. Source: Deploy from a branch
3. Branch: `gh-pages` / `/ (root)`
4. Save

## After Setup

The Helm workflow will automatically:
- Package charts from `examples/helm/`
- Update `index.yaml` in gh-pages branch
- Users can then install via:

```bash
helm repo add freeradius https://cepat-kilat-teknologi.github.io/freeradius-stack
helm install freeradius freeradius/freeradius
```
