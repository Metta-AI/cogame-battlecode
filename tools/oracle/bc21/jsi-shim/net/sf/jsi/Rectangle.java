// See SpatialIndex.java. A no-op stand-in for the dead `net.sf.jsi` artifact.
package net.sf.jsi;

public class Rectangle {
    public float minX, minY, maxX, maxY;

    public Rectangle(float x1, float y1, float x2, float y2) {
        this.minX = x1;
        this.minY = y1;
        this.maxX = x2;
        this.maxY = y2;
    }
}
