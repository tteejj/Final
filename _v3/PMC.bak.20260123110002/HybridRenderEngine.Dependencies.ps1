
# HybridRenderEngine Dependencies
# Extracted to separate file to ensure types are loaded before HybridRenderEngine.ps1 is parsed.

try {
    # Check if type exists to avoid Add-Type errors on reload
    [void][InternalStringBuilderPool_Backup]
} catch {
    Add-Type -TypeDefinition @'
    using System;
    using System.Text;
    using System.Collections.Concurrent;
    using System.Collections.Generic;

    public class InternalCachedWidget_Backup {
        public int X;
        public int Y;
        public int Width;
        public int Height;
        public int ZIndex;
        public string ContentHash;
        public object Cells; 

        public InternalCachedWidget_Backup(int x, int y, int w, int h, int z) {
            X = x; Y = y; Width = w; Height = h; ZIndex = z;
            ContentHash = "";
        }
    }

    public static class InternalStringBuilderPool_Backup {
        private static ConcurrentQueue<StringBuilder> _pool = new ConcurrentQueue<StringBuilder>();

        public static StringBuilder Get() {
            if (_pool.TryDequeue(out StringBuilder sb)) {
                sb.Clear();
                return sb;
            }
            return new StringBuilder(256);
        }

        public static void Recycle(StringBuilder sb) {
            if (sb != null) _pool.Enqueue(sb);
        }
    }
'@
    # Write-Host "DEBUG: HybridRenderEngine Dependencies Loaded." -ForegroundColor DarkGray
}
