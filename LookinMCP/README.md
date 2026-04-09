# LookinMCP

`LookinMCP` is a native macOS command-line MCP server for Lookin.

详细使用说明见：

- [Docs/LookinMCP使用说明.md](/Users/arthur/github/Lookin/Docs/LookinMCP使用说明.md)

推荐构建命令：

```sh
pod install
xcodebuild \
  -workspace Lookin.xcworkspace \
  -scheme LookinMCP \
  -configuration Debug \
  build \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR="$PWD/Build"
```

构建完成后：

- 可执行文件：`Build/Debug/LookinMCP`
- 运行期依赖：`Build/Frameworks`

`LookinMCP` uses MCP `stdio` transport. It does not start `NSApplicationMain` and does not open the Lookin window.
