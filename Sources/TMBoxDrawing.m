#import "TMBoxDrawing.h"

// Толщина сегментов (вверх, вправо, вниз, влево): 0 нет, 1 тонкая, 2 жирная, 3 двойная — для U+2500…U+257F
static const uint8_t kSeg[128][4] = {
    {0,1,0,1},{0,2,0,2},{1,0,1,0},{2,0,2,0},{0,1,0,1},{0,2,0,2},{1,0,1,0},{2,0,2,0},{0,1,0,1},{0,2,0,2},{1,0,1,0},{2,0,2,0},
    {0,1,1,0},{0,2,1,0},{0,1,2,0},{0,2,2,0},   // 250C…250F
    {0,0,1,1},{0,0,1,2},{0,0,2,1},{0,0,2,2},   // 2510…2513
    {1,1,0,0},{1,2,0,0},{2,1,0,0},{2,2,0,0},   // 2514…2517
    {1,0,0,1},{1,0,0,2},{2,0,0,1},{2,0,0,2},   // 2518…251B
    {1,1,1,0},{1,2,1,0},{2,1,1,0},{1,1,2,0},{2,1,2,0},{2,2,1,0},{1,2,2,0},{2,2,2,0},   // 251C…2523
    {1,0,1,1},{1,0,1,2},{2,0,1,1},{1,0,2,1},{2,0,2,1},{2,0,1,2},{1,0,2,2},{2,0,2,2},   // 2524…252B
    {0,1,1,1},{0,1,1,2},{0,2,1,1},{0,2,1,2},{0,1,2,1},{0,1,2,2},{0,2,2,1},{0,2,2,2},   // 252C…2533
    {1,1,0,1},{1,1,0,2},{1,2,0,1},{1,2,0,2},{2,1,0,1},{2,1,0,2},{2,2,0,1},{2,2,0,2},   // 2534…253B
    {1,1,1,1},{1,1,1,2},{1,2,1,1},{1,2,1,2},{2,1,1,1},{1,1,2,1},{2,1,2,1},{2,1,1,2},{2,2,1,1},{1,1,2,2},{1,2,2,1},{2,2,1,2},{1,2,2,2},{2,1,2,2},{2,2,2,1},{2,2,2,2},   // 253C…254B
    {0,1,0,1},{0,2,0,2},{1,0,1,0},{2,0,2,0},   // 254C…254F
    {0,3,0,3},{3,0,3,0},{0,3,1,0},{0,1,3,0},{0,3,3,0},{0,0,1,3},{0,0,3,1},{0,0,3,3},{1,3,0,0},{3,1,0,0},{3,3,0,0},{1,0,0,3},{3,0,0,1},{3,0,0,3},   // 2550…255D
    {1,3,1,0},{3,1,3,0},{3,3,3,0},{1,0,1,3},{3,0,3,1},{3,0,3,3},{0,3,1,3},{0,1,3,1},{0,3,3,3},{1,3,0,3},{3,1,0,1},{3,3,0,3},{1,3,1,3},{3,1,3,1},{3,3,3,3},   // 255E…256C
    {0,1,1,0},{0,0,1,1},{1,0,0,1},{1,1,0,0},   // 256D…2570 (скруглённые рисуем как прямые углы)
    {0,0,0,0},{0,0,0,0},{0,0,0,0},             // 2571…2573 (диагонали — отдельно)
    {0,0,0,1},{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,2},{2,0,0,0},{0,2,0,0},{0,0,2,0},{0,2,0,1},{1,0,2,0},{0,1,0,2},{2,0,1,0}   // 2574…257F
};

static void fill(CGContextRef c, CGFloat x, CGFloat y, CGFloat w, CGFloat h) { if (w > 0 && h > 0) CGContextFillRect(c, CGRectMake(x, y, w, h)); }

BOOL TMDrawBoxChar(CGContextRef ctx, uint32_t ch, CGRect r, CGFloat scale, CGColorRef color) {
    CGFloat px = 1.0 / scale;
    if (ch >= 0x2500 && ch <= 0x257f) {
        if (ch >= 0x2571 && ch <= 0x2573) {
            CGContextSetStrokeColorWithColor(ctx, color); CGContextSetLineWidth(ctx, MAX(px, r.size.width / 9));
            if (ch != 0x2572) { CGContextMoveToPoint(ctx, r.origin.x, CGRectGetMaxY(r)); CGContextAddLineToPoint(ctx, CGRectGetMaxX(r), r.origin.y); }
            if (ch != 0x2571) { CGContextMoveToPoint(ctx, r.origin.x, r.origin.y); CGContextAddLineToPoint(ctx, CGRectGetMaxX(r), CGRectGetMaxY(r)); }
            CGContextStrokePath(ctx); return YES;
        }
        const uint8_t *s = kSeg[ch - 0x2500];
        CGFloat light = MAX(px, round(r.size.width / 8 * scale) / scale), heavy = light * 2.2;
        CGFloat cx = round((r.origin.x + r.size.width / 2) * scale) / scale, cy = round((r.origin.y + r.size.height / 2) * scale) / scale;
        CGContextSetFillColorWithColor(ctx, color);
        CGFloat x0 = r.origin.x, x1 = CGRectGetMaxX(r), y0 = r.origin.y, y1 = CGRectGetMaxY(r);
        for (int k = 0; k < 4; k++) {
            int wgt = s[k]; if (!wgt) continue;
            CGFloat t = wgt == 2 ? heavy : light;
            if (wgt == 3) {   // двойная линия: две параллельные тонкие, смещённые от оси
                CGFloat d = light * 1.1;
                for (int side = -1; side <= 1; side += 2) {
                    CGFloat o = side * d;
                    switch (k) {
                        case 0: fill(ctx, cx + o - light / 2, y0, light, cy - y0 + (s[1] == 3 || s[3] == 3 ? d + light / 2 : light / 2)); break;
                        case 2: fill(ctx, cx + o - light / 2, cy - (s[1] == 3 || s[3] == 3 ? d + light / 2 : light / 2), light, y1 - cy + (s[1] == 3 || s[3] == 3 ? d + light / 2 : light / 2)); break;
                        case 1: fill(ctx, cx - (s[0] == 3 || s[2] == 3 ? d + light / 2 : light / 2), cy + o - light / 2, x1 - cx + (s[0] == 3 || s[2] == 3 ? d + light / 2 : light / 2), light); break;
                        case 3: fill(ctx, x0, cy + o - light / 2, cx - x0 + (s[0] == 3 || s[2] == 3 ? d + light / 2 : light / 2), light); break;
                    }
                }
                continue;
            }
            switch (k) {
                case 0: fill(ctx, cx - t / 2, y0, t, cy - y0 + t / 2); break;
                case 1: fill(ctx, cx - t / 2, cy - t / 2, x1 - cx + t / 2, t); break;
                case 2: fill(ctx, cx - t / 2, cy - t / 2, t, y1 - cy + t / 2); break;
                case 3: fill(ctx, x0, cy - t / 2, cx - x0 + t / 2, t); break;
            }
        }
        return YES;
    }
    if (ch >= 0x2580 && ch <= 0x259f) {
        CGFloat x = r.origin.x, y = r.origin.y, w = r.size.width, h = r.size.height;
        CGContextSetFillColorWithColor(ctx, color);
        if (ch == 0x2580) fill(ctx, x, y, w, h / 2);
        else if (ch >= 0x2581 && ch <= 0x2587) { CGFloat hh = h * (ch - 0x2580) / 8; fill(ctx, x, y + h - hh, w, hh); }
        else if (ch == 0x2588) fill(ctx, x, y, w, h);
        else if (ch >= 0x2589 && ch <= 0x258f) { CGFloat ww = w * (0x2590 - ch) / 8; fill(ctx, x, y, ww, h); }
        else if (ch == 0x2590) fill(ctx, x + w / 2, y, w / 2, h);
        else if (ch >= 0x2591 && ch <= 0x2593) { CGContextSaveGState(ctx); CGContextSetAlpha(ctx, ch == 0x2591 ? 0.25 : ch == 0x2592 ? 0.5 : 0.75); fill(ctx, x, y, w, h); CGContextRestoreGState(ctx); }
        else if (ch == 0x2594) fill(ctx, x, y, w, h / 8);
        else if (ch == 0x2595) fill(ctx, x + w * 7 / 8, y, w / 8, h);
        else {
            static const uint8_t q[10] = {4, 8, 1, 13, 9, 7, 11, 2, 6, 14};   // биты: 1 лв-верх, 2 пр-верх, 4 лв-низ, 8 пр-низ; 2596…259F
            int m = q[ch - 0x2596];
            if (m & 1) fill(ctx, x, y, w / 2, h / 2); if (m & 2) fill(ctx, x + w / 2, y, w / 2, h / 2);
            if (m & 4) fill(ctx, x, y + h / 2, w / 2, h / 2); if (m & 8) fill(ctx, x + w / 2, y + h / 2, w / 2, h / 2);
        }
        return YES;
    }
    if (ch >= 0xe0b0 && ch <= 0xe0b3) {   // Powerline: треугольники и шевроны
        CGFloat x0 = r.origin.x, x1 = CGRectGetMaxX(r), y0 = r.origin.y, y1 = CGRectGetMaxY(r), ym = (y0 + y1) / 2;
        CGContextSetFillColorWithColor(ctx, color); CGContextSetStrokeColorWithColor(ctx, color); CGContextSetLineWidth(ctx, MAX(px, r.size.width / 9));
        if (ch == 0xe0b0) { CGContextMoveToPoint(ctx, x0, y0); CGContextAddLineToPoint(ctx, x1, ym); CGContextAddLineToPoint(ctx, x0, y1); CGContextFillPath(ctx); }
        else if (ch == 0xe0b2) { CGContextMoveToPoint(ctx, x1, y0); CGContextAddLineToPoint(ctx, x0, ym); CGContextAddLineToPoint(ctx, x1, y1); CGContextFillPath(ctx); }
        else if (ch == 0xe0b1) { CGContextMoveToPoint(ctx, x0, y0); CGContextAddLineToPoint(ctx, x1, ym); CGContextAddLineToPoint(ctx, x0, y1); CGContextStrokePath(ctx); }
        else { CGContextMoveToPoint(ctx, x1, y0); CGContextAddLineToPoint(ctx, x0, ym); CGContextAddLineToPoint(ctx, x1, y1); CGContextStrokePath(ctx); }
        return YES;
    }
    return NO;
}
