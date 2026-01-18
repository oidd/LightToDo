/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 */

import type { JSX } from 'react';

import './ColorPicker.css';

import * as React from 'react';

import { isKeyboardInput } from '../utils/focusUtils';

interface ColorPickerProps {
  color: string;
  onChange?: (
    value: string,
    skipHistoryStack: boolean,
    skipRefocus: boolean,
  ) => void;
}

// 8 colors: transparent + 7 fixed colors
const basicColors = [
  '',            // 默认颜色（移除自定义色彩）
  '#989898',     // 灰色
  '#e14a54',     // 红色
  '#ef8834',     // 橙色
  '#f2c343',     // 黄色
  '#58b05c',     // 绿色
  '#5bb5f7',     // 蓝色
  '#d24be2',     // 紫色
];

export default function ColorPicker({
  color,
  onChange,
}: Readonly<ColorPickerProps>): JSX.Element {
  const innerDivRef = React.useRef(null);

  const emitOnChange = (newColor: string, skipRefocus: boolean = false) => {
    if (innerDivRef.current !== null && onChange) {
      onChange(newColor, false, skipRefocus);
    }
  };

  const onBasicColorClick = (e: React.MouseEvent, basicColor: string) => {
    emitOnChange(basicColor, isKeyboardInput(e));
  };

  return (
    <div
      className="color-picker-wrapper"
      ref={innerDivRef}>
      <div className="color-picker-basic-color">
        {basicColors.map((basicColor, index) => {
          const isSelected = basicColor === ''
            ? (color === '' || color === 'rgb(0, 0, 0)' || color === '#000000' || color === 'transparent')
            : (color !== '' && toHex(color) === toHex(basicColor));

          return (
            <button
              className={`color-picker-btn${isSelected ? ' active' : ''}${basicColor === '' ? ' transparent' : ''}`}
              key={basicColor + index}
              style={basicColor === '' ? undefined : { backgroundColor: basicColor }}
              onClick={(e) => onBasicColorClick(e, basicColor)}
              title={basicColor === '' ? '默认颜色' : basicColor}
            />
          );
        })}
      </div>
    </div>
  );
}

export function toHex(value: string): string {
  if (!value.startsWith('#')) {
    const ctx = document.createElement('canvas').getContext('2d');

    if (!ctx) {
      throw new Error('2d context not supported or canvas already initialized');
    }

    ctx.fillStyle = value;

    return ctx.fillStyle;
  } else if (value.length === 4 || value.length === 5) {
    value = value
      .split('')
      .map((v, i) => (i ? v + v : '#'))
      .join('');

    return value;
  } else if (value.length === 7 || value.length === 9) {
    return value;
  }

  return '#000000';
}
