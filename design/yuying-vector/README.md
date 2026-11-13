# 予盈可编辑图标

按用户最新上传的文字要求，以品牌参考中的墨黑书页、两层浅米纸页和暖白纸张底重新绘制。AppIcon.svg 为独立的矢量贝塞尔源稿，不包含截图、内嵌位图或文字；画布为无预烘焙圆角的完整正方形。图层分别标明背景、两层纸页和墨黑书页，可在矢量编辑器调整。

BrandSymbol.svg 由相同路径派生，供启动页和 App 内标志使用。正式 AppIcon.png 为 1024×1024、RGB、无 alpha；60 与 180 像素预览仅供检查识别度。

可重复导出：

```bash
python3 -m venv --system-site-packages /tmp/yuying-svg-render
/tmp/yuying-svg-render/bin/pip install CairoSVG==2.8.2
/tmp/yuying-svg-render/bin/python scripts/render-brand-assets.py
```

渲染工具只用于开发环境，不增加 App 的依赖。源稿及生成图的 SHA256 见 asset-lock.json。原先提供 PNG 的 Build 31 产物保留为历史记录；最新文字要求适用于本次矢量图标交付。
