/*
 * Copyright (c) 2016 Bilibili
 * copyright (c) 2016 Zhang Rui <bbcallen@gmail.com>
 *
 * This file is part of ijkPlayer.
 *
 * ijkPlayer is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * ijkPlayer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with ijkPlayer; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <math.h>
#include <memory.h>

/*! @abstract A matrix with 4 rows and 4 columns.                             */
typedef struct { float x;float y;float z; } ijk_float3_vector;
typedef struct { float c1;float c2;float c3;float c4; } ijk_float4_vector;

typedef struct { float e[4][4]; } ijk_float4x4_matrix;

static ijk_float3_vector vector_make_float3(float x, float y, float z) {
    return (ijk_float3_vector){ x, y, z };
}

static ijk_float4x4_matrix matrix_make_rows(
             float m00, float m10, float m20, float m30,
             float m01, float m11, float m21, float m31,
             float m02, float m12, float m22, float m32,
             float m03, float m13, float m23, float m33) {
    return (ijk_float4x4_matrix)
    {{
        { m00, m01, m02, m03 },     // each line here provides column data
        { m10, m11, m12, m13 },
        { m20, m21, m22, m23 },
        { m30, m31, m32, m33 }
    }};
}

static ijk_float4x4_matrix ijk_make_matrix_fromArr(
             float m[16]) {
    return (ijk_float4x4_matrix)
    {{
        { m[0], m[4], m[8],  m[12] },     // each line here provides column data
        { m[1], m[5], m[9],  m[13] },
        { m[2], m[6], m[10], m[14] },
        { m[3], m[7], m[11], m[15] }
    }};
}


static ijk_float4x4_matrix matrix4x4_rotation(float radians, ijk_float3_vector axis) {
    float ct = cosf(radians);
    float st = sinf(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;
    return matrix_make_rows(
                        ct + x * x * ci, x * y * ci - z * st, x * z * ci + y * st, 0,
                    y * x * ci + z * st,     ct + y * y * ci, y * z * ci - x * st, 0,
                    z * x * ci - y * st, z * y * ci + x * st,     ct + z * z * ci, 0,
                                      0,                   0,                   0, 1);
}

static ijk_float4x4_matrix matrix4x4_rotation_xyz(float radians, float x, float y, float z) {
    return matrix4x4_rotation(radians, vector_make_float3(x, y, z));
}

static void ijk_matrix_multiply(const ijk_float4x4_matrix * m, const ijk_float4x4_matrix * n, ijk_float4x4_matrix * r)
{
    unsigned int i, j, k;

    memset(r, 0x0, sizeof(ijk_float4x4_matrix));
    int size = 4;

    for (i = 0; i < size; ++i) {
        for (j = 0; j < size; ++j) {
            for (k = 0; k < size; ++k) {
                r->e[i][j] +=
                    m->e[i][k] * n->e[k][j];
            }
        }
    }
}

static float degrees_from_radians(float radians) {
    return (radians / M_PI) * 180;
}

static float radians_from_degrees(float degrees) {
    return (degrees / 180) * M_PI;
}
