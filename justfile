# macOS Permissions VS Code Extension

# Install .vsix into VS Code
install: package
    code --install-extension macos-permissions-*.vsix --force

# Compile TypeScript
build:
    npx tsc -p ./

# Compile and rebuild native prebuild
build-native:
    npx prebuildify --napi --strip

# Run tests
test:
    npx tsc -p tsconfig.test.json
    npx mocha out/test/**/*.test.js --ui tdd --timeout 10000

# Lint source
lint:
    npx eslint src --ext ts

# Package as .vsix
package: clean build build-native
    npx vsce package


# Watch mode for development
watch:
    npx tsc -watch -p ./

# Remove build artifacts
clean:
    rm -rf out build *.vsix
