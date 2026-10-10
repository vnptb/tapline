// Usage: svg2png <in.svg> <out.png> [size=1024]
// Renders an SVG through WebKit (full SVG support: gradients, masks, filters, blend modes)
// with a transparent background into a PNG of exactly size×size pixels.
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: svg2png in.svg out.png [size]")
    exit(1)
}
let svgURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let size = args.count > 3 ? Int(args[3]) ?? 1024 : 1024

guard let svg = try? String(contentsOf: svgURL, encoding: .utf8) else {
    print("cannot read \(svgURL.path)")
    exit(1)
}

let html = """
<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:transparent;overflow:hidden}
#w{width:\(size)px;height:\(size)px}
#w>svg{width:\(size)px;height:\(size)px;display:block}
</style></head><body><div id="w">\(svg)</div></body></html>
"""

final class Renderer: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let window: NSWindow
    init(size: Int) {
        let frame = NSRect(x: 0, y: 0, width: size, height: size)
        web = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        web.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = web
        super.init()
        web.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.snap() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("load failed: \(error)")
        exit(1)
    }

    func snap() {
        let cfg = WKSnapshotConfiguration()
        cfg.rect = NSRect(x: 0, y: 0, width: size, height: size)
        cfg.afterScreenUpdates = true
        web.takeSnapshot(with: cfg) { image, error in
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                print("snapshot failed: \(String(describing: error))")
                exit(1)
            }
            // normalise to exactly size×size pixels
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
            let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
            CGImageDestinationFinalize(dest)
            print("svg2png: \(outURL.path) (\(size)x\(size), snapshot \(cg.width)x\(cg.height))")
            exit(0)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer(size: size)
renderer.web.loadHTMLString(html, baseURL: svgURL.deletingLastPathComponent())
DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
    print("timeout")
    exit(1)
}
app.run()
