import { useRef, useEffect, useState, useCallback, forwardRef, useImperativeHandle } from 'react';
import { Renderer, Program, Triangle, Mesh } from 'ogl';
import './LightRays.css';

const DEFAULT_COLOR = '#ffffff';

const hexToRgb = (hex: string): [number, number, number] => {
    const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    return m ? [parseInt(m[1], 16) / 255, parseInt(m[2], 16) / 255, parseInt(m[3], 16) / 255] : [1, 1, 1];
};

const colorNameToHex = (colorName: string): string => {
    switch (colorName) {
        case 'blue': return '#90caf9';
        case 'green': return '#a5d6a7';
        case 'red': return '#ef9a9a';
        case 'yellow': return '#fff59d';
        case 'purple': return '#ce93d8';
        case 'pink': return '#f48fb1';
        case 'gray': return '#b0bec5';
        case 'orange':
        default: return '#ffcc80';
    }
};

const getAnchorAndDir = (origin: string, w: number, h: number) => {
    const outside = 0.2;
    switch (origin) {
        case 'left':
            return { anchor: [-outside * w, 0.5 * h], dir: [1, 0] };
        case 'right':
            return { anchor: [(1 + outside) * w, 0.5 * h], dir: [-1, 0] };
        default:
            return { anchor: [0.5 * w, -outside * h], dir: [0, 1] };
    }
};

export interface LightRaysHandle {
    show: (edge: 'left' | 'right', colorName: string) => void;
    hide: () => void;
}

interface LightRaysProps {
    raysSpeed?: number;
    lightSpread?: number;
    rayLength?: number;
    pulsating?: boolean;
    fadeDistance?: number;
    saturation?: number;
}

const LightRays = forwardRef<LightRaysHandle, LightRaysProps>(({
    raysSpeed = 2.8,
    lightSpread = 2,
    rayLength = 3,
    pulsating = false,
    fadeDistance = 2,
    saturation = 1.5
}, ref) => {
    const containerRef = useRef<HTMLDivElement>(null);
    const uniformsRef = useRef<any>(null);
    const rendererRef = useRef<Renderer | null>(null);
    const animationIdRef = useRef<number | null>(null);
    const meshRef = useRef<Mesh | null>(null);
    const cleanupFunctionRef = useRef<(() => void) | null>(null);

    const [visible, setVisible] = useState(false);
    const [raysOrigin, setRaysOrigin] = useState<'left' | 'right'>('right');
    const [raysColor, setRaysColor] = useState('#ffcc80');

    const show = useCallback((edge: 'left' | 'right', colorName: string) => {
        setRaysOrigin(edge);
        setRaysColor(colorNameToHex(colorName));
        setVisible(true);
    }, []);

    const hide = useCallback(() => {
        setVisible(false);
    }, []);

    useImperativeHandle(ref, () => ({
        show,
        hide
    }), [show, hide]);

    useEffect(() => {
        if (!visible || !containerRef.current) return;

        if (cleanupFunctionRef.current) {
            cleanupFunctionRef.current();
            cleanupFunctionRef.current = null;
        }

        const initializeWebGL = async () => {
            if (!containerRef.current) return;

            await new Promise(resolve => setTimeout(resolve, 10));
            if (!containerRef.current) return;

            const renderer = new Renderer({
                dpr: Math.min(window.devicePixelRatio, 2),
                alpha: true
            });
            rendererRef.current = renderer;

            const gl = renderer.gl;
            gl.canvas.style.width = '100%';
            gl.canvas.style.height = '100%';

            while (containerRef.current.firstChild) {
                containerRef.current.removeChild(containerRef.current.firstChild);
            }
            containerRef.current.appendChild(gl.canvas);

            const vert = `
attribute vec2 position;
varying vec2 vUv;
void main() {
  vUv = position * 0.5 + 0.5;
  gl_Position = vec4(position, 0.0, 1.0);
}`;

            const frag = `precision highp float;

uniform float iTime;
uniform vec2  iResolution;

uniform vec2  rayPos;
uniform vec2  rayDir;
uniform vec3  raysColor;
uniform float raysSpeed;
uniform float lightSpread;
uniform float rayLength;
uniform float pulsating;
uniform float fadeDistance;
uniform float saturation;

varying vec2 vUv;

float rayStrength(vec2 raySource, vec2 rayRefDirection, vec2 coord,
                  float seedA, float seedB, float speed) {
  vec2 sourceToCoord = coord - raySource;
  vec2 dirNorm = normalize(sourceToCoord);
  float cosAngle = dot(dirNorm, rayRefDirection);
  
  float spreadFactor = pow(max(cosAngle, 0.0), 1.0 / max(lightSpread, 0.001));

  float distance = length(sourceToCoord);
  float maxDistance = iResolution.x * rayLength;
  float lengthFalloff = clamp((maxDistance - distance) / maxDistance, 0.0, 1.0);
  
  float fadeFalloff = clamp((iResolution.x * fadeDistance - distance) / (iResolution.x * fadeDistance), 0.5, 1.0);
  float pulse = pulsating > 0.5 ? (0.8 + 0.2 * sin(iTime * speed * 3.0)) : 1.0;

  float baseStrength = clamp(
    (0.45 + 0.15 * sin(cosAngle * seedA + iTime * speed)) +
    (0.3 + 0.2 * cos(-cosAngle * seedB + iTime * speed)),
    0.0, 1.0
  );

  return baseStrength * lengthFalloff * fadeFalloff * spreadFactor * pulse;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 coord = vec2(fragCoord.x, iResolution.y - fragCoord.y);

  vec4 rays1 = vec4(1.0) *
               rayStrength(rayPos, rayDir, coord, 36.2214, 21.11349,
                           1.5 * raysSpeed);
  vec4 rays2 = vec4(1.0) *
               rayStrength(rayPos, rayDir, coord, 22.3991, 18.0234,
                           1.1 * raysSpeed);

  fragColor = rays1 * 0.5 + rays2 * 0.4;

  float brightness = 1.0 - (coord.y / iResolution.y);
  fragColor.x *= 0.1 + brightness * 0.8;
  fragColor.y *= 0.3 + brightness * 0.6;
  fragColor.z *= 0.5 + brightness * 0.5;

  if (saturation != 1.0) {
    float gray = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
    fragColor.rgb = mix(vec3(gray), fragColor.rgb, saturation);
  }

  fragColor.rgb *= raysColor;
}

void main() {
  vec4 color;
  mainImage(color, gl_FragCoord.xy);
  gl_FragColor = color;
}`;

            const uniforms = {
                iTime: { value: 0 },
                iResolution: { value: [1, 1] },
                rayPos: { value: [0, 0] },
                rayDir: { value: [0, 1] },
                raysColor: { value: hexToRgb(raysColor) },
                raysSpeed: { value: raysSpeed },
                lightSpread: { value: lightSpread },
                rayLength: { value: rayLength },
                pulsating: { value: pulsating ? 1.0 : 0.0 },
                fadeDistance: { value: fadeDistance },
                saturation: { value: saturation }
            };
            uniformsRef.current = uniforms;

            const geometry = new Triangle(gl);
            const program = new Program(gl, {
                vertex: vert,
                fragment: frag,
                uniforms
            });
            const mesh = new Mesh(gl, { geometry, program });
            meshRef.current = mesh;

            const updatePlacement = () => {
                if (!containerRef.current || !renderer) return;

                renderer.dpr = Math.min(window.devicePixelRatio, 2);

                const { clientWidth: wCSS, clientHeight: hCSS } = containerRef.current;
                renderer.setSize(wCSS, hCSS);

                const dpr = renderer.dpr;
                const w = wCSS * dpr;
                const h = hCSS * dpr;

                uniforms.iResolution.value = [w, h];

                const { anchor, dir } = getAnchorAndDir(raysOrigin, w, h);
                uniforms.rayPos.value = anchor;
                uniforms.rayDir.value = dir;
            };

            const loop = (t: number) => {
                if (!rendererRef.current || !uniformsRef.current || !meshRef.current) {
                    return;
                }

                uniforms.iTime.value = t * 0.001;

                try {
                    renderer.render({ scene: mesh });
                    animationIdRef.current = requestAnimationFrame(loop);
                } catch (error) {
                    console.warn('WebGL rendering error:', error);
                    return;
                }
            };

            window.addEventListener('resize', updatePlacement);
            updatePlacement();
            animationIdRef.current = requestAnimationFrame(loop);

            cleanupFunctionRef.current = () => {
                if (animationIdRef.current) {
                    cancelAnimationFrame(animationIdRef.current);
                    animationIdRef.current = null;
                }

                window.removeEventListener('resize', updatePlacement);

                if (renderer) {
                    try {
                        const canvas = renderer.gl.canvas;
                        const loseContextExt = renderer.gl.getExtension('WEBGL_lose_context');
                        if (loseContextExt) {
                            loseContextExt.loseContext();
                        }

                        if (canvas && canvas.parentNode) {
                            canvas.parentNode.removeChild(canvas);
                        }
                    } catch (error) {
                        console.warn('Error during WebGL cleanup:', error);
                    }
                }

                rendererRef.current = null;
                uniformsRef.current = null;
                meshRef.current = null;
            };
        };

        initializeWebGL();

        return () => {
            if (cleanupFunctionRef.current) {
                cleanupFunctionRef.current();
                cleanupFunctionRef.current = null;
            }
        };
    }, [visible, raysOrigin, raysColor, raysSpeed, lightSpread, rayLength, pulsating, fadeDistance, saturation]);

    // Update uniforms when props change
    useEffect(() => {
        if (!uniformsRef.current || !containerRef.current || !rendererRef.current) return;

        const u = uniformsRef.current;
        const renderer = rendererRef.current;

        u.raysColor.value = hexToRgb(raysColor);
        u.raysSpeed.value = raysSpeed;
        u.lightSpread.value = lightSpread;
        u.rayLength.value = rayLength;
        u.pulsating.value = pulsating ? 1.0 : 0.0;
        u.fadeDistance.value = fadeDistance;
        u.saturation.value = saturation;

        const { clientWidth: wCSS, clientHeight: hCSS } = containerRef.current;
        const dpr = renderer.dpr;
        const { anchor, dir } = getAnchorAndDir(raysOrigin, wCSS * dpr, hCSS * dpr);
        u.rayPos.value = anchor;
        u.rayDir.value = dir;
    }, [raysColor, raysSpeed, lightSpread, raysOrigin, rayLength, pulsating, fadeDistance, saturation]);

    if (!visible) return null;

    return <div ref={containerRef} className="light-rays-container" />;
});

export default LightRays;
