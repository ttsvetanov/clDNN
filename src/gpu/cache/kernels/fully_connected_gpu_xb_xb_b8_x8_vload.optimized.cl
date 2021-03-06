// Copyright (c) 2016-2017 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.


#if RELU
    #define ACTIVATION(output, input) output = isinf(NEGATIVE_SLOPE) ? ((input >= 0.0f) ? \
    input : -NEGATIVE_SLOPE) : (max(input, 0.0f) + NEGATIVE_SLOPE * min(input, 0.0f));
#else
    #define ACTIVATION(output, input) output = input;
#endif

#define MULTIPLY_BLOCKS_8x8(_result, _blockA, _blockB)  \
{   \
    const float8 acol0 = TRANSPOSE_BLOCK_8_COL( _blockA, 0 ); \
    const float8 acol1 = TRANSPOSE_BLOCK_8_COL( _blockA, 1 ); \
    const float8 acol2 = TRANSPOSE_BLOCK_8_COL( _blockA, 2 ); \
    const float8 acol3 = TRANSPOSE_BLOCK_8_COL( _blockA, 3 ); \
    const float8 acol4 = TRANSPOSE_BLOCK_8_COL( _blockA, 4 ); \
    const float8 acol5 = TRANSPOSE_BLOCK_8_COL( _blockA, 5 ); \
    const float8 acol6 = TRANSPOSE_BLOCK_8_COL( _blockA, 6 ); \
    const float8 acol7 = TRANSPOSE_BLOCK_8_COL( _blockA, 7 ); \
    _result = mad( _blockB.s0, acol0, _result ); \
    _result = mad( _blockB.s1, acol1, _result ); \
    _result = mad( _blockB.s2, acol2, _result ); \
    _result = mad( _blockB.s3, acol3, _result ); \
    _result = mad( _blockB.s4, acol4, _result ); \
    _result = mad( _blockB.s5, acol5, _result ); \
    _result = mad( _blockB.s6, acol6, _result ); \
    _result = mad( _blockB.s7, acol7, _result ); \
}

#define SUB_GROUP_SIZE 8

__attribute__((reqd_work_group_size(SUB_GROUP_SIZE, 1, 1)))
KERNEL (fully_connected_gpu_xb_xb_b8_x8_vload)(
    const __global float* input,
    __global float* output,
    const __global float* weight
#if BIAS_TERM
    , __global UNIT_TYPE* bias)
#else
    )
#endif
{
    const uint global_id = get_global_id(0);
    const uint group_id = get_global_id(1); // which part of batches we are computing, for example for batch 64 we compute batches 0..31 for group_id == 0 and batches 32..65 for group_id == 1
    uint sub_group_idx = (uint)get_local_id(0) % 8;

    const uint out_id = (sub_group_idx * BATCHES_PER_WORK_ITEM * (uint)get_global_size(1)) / 8 + (global_id / 8) * BATCHES_PER_WORK_ITEM * NEURONS_PER_WORK_ITEM * (uint)get_global_size(1) + (BATCHES_PER_WORK_ITEM * group_id) / 8;

    uint neuronIdx = sub_group_idx + (global_id / 8) * 8 * NEURONS_PER_WORK_ITEM;

    float8 blockC00 = 0.f;
    float8 blockC10 = 0.f;

#if BATCHES_PER_WORK_ITEM >= 16
    float8 blockC01 = 0.f;
    float8 blockC11 = 0.f;
#endif

#if BATCHES_PER_WORK_ITEM >= 32
    float8 blockC02 = 0.f;
    float8 blockC12 = 0.f;

    float8 blockC03 = 0.f;
    float8 blockC13 = 0.f;
#endif

    uint weight_offset = neuronIdx;
#if NEURONS_PER_WORK_ITEM > 1

    uint weight_offset2 = neuronIdx + 8;

#endif // #if NEURONS_PER_WORK_ITEM > 1

    uint input_idx = sub_group_idx * (BATCHES_PER_WORK_ITEM / 8) * (uint)get_global_size(1) + (group_id * BATCHES_PER_WORK_ITEM) / 8;
    for(uint h = 0; h < INPUT_ELEMENTS_COUNT / 8; h++)
    {
        float8 blockA00 = vload8(input_idx, input);

#if BATCHES_PER_WORK_ITEM >= 16
        float8 blockA01 = vload8(input_idx + 1, input);
#endif

#if BATCHES_PER_WORK_ITEM >= 32
        float8 blockA02 = vload8(input_idx + 2, input);
        float8 blockA03 = vload8(input_idx + 3, input);
#endif
        float8 blockB00;
        blockB00.s0 = weight[weight_offset]; weight_offset += WEIGHTS_BATCH_NUM;
        blockB00.s1 = weight[weight_offset]; weight_offset += WEIGHTS_BATCH_NUM;
        blockB00.s2 = weight[weight_offset]; weight_offset += WEIGHTS_BATCH_NUM;
        blockB00.s3 = weight[weight_offset]; weight_offset += WEIGHTS_BATCH_NUM;
        blockB00.s4 = weight[weight_offset]; weight_offset += WEIGHTS_BATCH_NUM;
        blockB00.s5 = weight[weight_offset]; weight_offset += WEIGHTS_BATCH_NUM;
        blockB00.s6 = weight[weight_offset]; weight_offset += WEIGHTS_BATCH_NUM;
        blockB00.s7 = weight[weight_offset]; weight_offset += WEIGHTS_BATCH_NUM;
        MULTIPLY_BLOCKS_8x8(blockC00, blockA00, blockB00)

#if BATCHES_PER_WORK_ITEM >= 16
        MULTIPLY_BLOCKS_8x8(blockC01, blockA01, blockB00)
#endif

#if BATCHES_PER_WORK_ITEM >= 32
        MULTIPLY_BLOCKS_8x8(blockC02, blockA02, blockB00)
        MULTIPLY_BLOCKS_8x8(blockC03, blockA03, blockB00)
#endif

#if NEURONS_PER_WORK_ITEM > 1

        float8 blockB10;
        blockB10.s0 = weight[weight_offset2]; weight_offset2 += WEIGHTS_BATCH_NUM;
        blockB10.s1 = weight[weight_offset2]; weight_offset2 += WEIGHTS_BATCH_NUM;
        blockB10.s2 = weight[weight_offset2]; weight_offset2 += WEIGHTS_BATCH_NUM;
        blockB10.s3 = weight[weight_offset2]; weight_offset2 += WEIGHTS_BATCH_NUM;
        blockB10.s4 = weight[weight_offset2]; weight_offset2 += WEIGHTS_BATCH_NUM;
        blockB10.s5 = weight[weight_offset2]; weight_offset2 += WEIGHTS_BATCH_NUM;
        blockB10.s6 = weight[weight_offset2]; weight_offset2 += WEIGHTS_BATCH_NUM;
        blockB10.s7 = weight[weight_offset2]; weight_offset2 += WEIGHTS_BATCH_NUM;
        MULTIPLY_BLOCKS_8x8(blockC10, blockA00, blockB10)

#if BATCHES_PER_WORK_ITEM >= 16
        MULTIPLY_BLOCKS_8x8(blockC11, blockA01, blockB10)
#endif
#if BATCHES_PER_WORK_ITEM >= 32
        MULTIPLY_BLOCKS_8x8(blockC12, blockA02, blockB10)
        MULTIPLY_BLOCKS_8x8(blockC13, blockA03, blockB10)
#endif

#endif // #if NEURONS_PER_WORK_ITEM > 1
        input_idx += INPUT_BATCH_NUM; // we don't need to multiply by 8 because of vload8
    }

#if BIAS_TERM
    blockC00 += bias[neuronIdx];
#if BATCHES_PER_WORK_ITEM >= 16
    blockC01 += bias[neuronIdx];
#endif

#if BATCHES_PER_WORK_ITEM >= 32
    blockC02 += bias[neuronIdx];
    blockC03 += bias[neuronIdx];
#endif

#if NEURONS_PER_WORK_ITEM > 1

    blockC10 += bias[neuronIdx+8];
#if BATCHES_PER_WORK_ITEM >= 16
    blockC11 += bias[neuronIdx+8];
#endif
#if BATCHES_PER_WORK_ITEM >= 32
    blockC12 += bias[neuronIdx+8];
    blockC13 += bias[neuronIdx+8];
#endif

#endif // #if NEURONS_PER_WORK_ITEM > 1

    ACTIVATION(blockC00, blockC00);
#if BATCHES_PER_WORK_ITEM >= 16
    ACTIVATION(blockC01, blockC01);
#endif
#if BATCHES_PER_WORK_ITEM >= 32
    ACTIVATION(blockC02, blockC02);
    ACTIVATION(blockC03, blockC03);
#endif

#if NEURONS_PER_WORK_ITEM > 1

    ACTIVATION(blockC10, blockC10);
#if BATCHES_PER_WORK_ITEM >= 16
    ACTIVATION(blockC11, blockC11);
#endif
#if BATCHES_PER_WORK_ITEM >= 32
    ACTIVATION(blockC12, blockC12);
    ACTIVATION(blockC13, blockC13);
#endif

#endif // #if NEURONS_PER_WORK_ITEM > 1

    vstore8(blockC00, out_id, output);
#if BATCHES_PER_WORK_ITEM >= 16
    vstore8(blockC01, out_id + 1, output);
#endif
#if BATCHES_PER_WORK_ITEM >= 32
    vstore8(blockC02, out_id + 2, output);
    vstore8(blockC03, out_id + 3, output);
#endif
#endif // #if BIAS_TERM
#if NEURONS_PER_WORK_ITEM > 1

    vstore8(blockC10, out_id+INPUT_BATCH_NUM, output);

#if BATCHES_PER_WORK_ITEM >= 16
    vstore8(blockC11, out_id+INPUT_BATCH_NUM+1, output);
#endif

#if BATCHES_PER_WORK_ITEM >= 32
    vstore8(blockC12, out_id+INPUT_BATCH_NUM+2, output);
    vstore8(blockC13, out_id+INPUT_BATCH_NUM+3, output);
#endif

#endif // #if NEURONS_PER_WORK_ITEM > 1
}

#undef MULTIPLY_BLOCKS_8x8
#undef ACTIVATION
