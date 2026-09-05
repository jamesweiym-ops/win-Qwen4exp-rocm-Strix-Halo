#include "llama-mmap.h"
#include "llama-model-loader.h"

#undef NDEBUG
#include <cassert>

int main() {
    const llama_mmap::ranges lazy = {{100, 200}, {400, 500}};
    const auto ranges = llama_mmap::initial_prefetch_ranges(600, lazy, 600);

    assert(ranges.size() == 3);
    const std::pair<size_t, size_t> expected0{0, 100};
    const std::pair<size_t, size_t> expected1{200, 400};
    const std::pair<size_t, size_t> expected2{500, 600};
    assert(ranges[0] == expected0);
    assert(ranges[1] == expected1);
    assert(ranges[2] == expected2);

    // A pager-owned tensor must be excluded even when the user did not enable
    // the policy-driven --tensor-read-lazy mode.
    assert(llama_model_loader::should_exclude_from_prefetch(
        llama_model_loader::TENSOR_NO_PREFETCH, true, LLAMA_TENSOR_READ_LAZY_OFF, 1024));
    assert(!llama_model_loader::should_exclude_from_prefetch(
        llama_model_loader::TENSOR_NO_PREFETCH, false, LLAMA_TENSOR_READ_LAZY_OFF, 1024));
    assert(!llama_model_loader::should_exclude_from_prefetch(
        llama_model_loader::TENSOR_READ_LAZY, true, LLAMA_TENSOR_READ_LAZY_OFF, 1024));
    assert(llama_model_loader::should_exclude_from_prefetch(
        llama_model_loader::TENSOR_READ_LAZY, true, LLAMA_TENSOR_READ_LAZY_ON, 1024));
    assert(!llama_model_loader::should_exclude_from_prefetch(
        llama_model_loader::TENSOR_READ_LAZY, true, LLAMA_TENSOR_READ_LAZY_AUTO, 4ull*1024*1024*1024));
    assert(llama_model_loader::should_exclude_from_prefetch(
        llama_model_loader::TENSOR_READ_LAZY, true, LLAMA_TENSOR_READ_LAZY_AUTO, 4ull*1024*1024*1024 + 1));

    return 0;
}
