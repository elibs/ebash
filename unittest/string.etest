#!/usr/bin/env bash

ETEST_to_upper_snake_case_units_end()
{
    assert_eq "NODE_KB" $(to_upper_snake_case "nodeKB")
    assert_eq "NODE_MB" $(to_upper_snake_case "nodeMB")
    assert_eq "NODE_GB" $(to_upper_snake_case "nodeGB")
    assert_eq "NODE_TB" $(to_upper_snake_case "nodeTB")
}

ETEST_to_upper_snake_case_units_middle()
{
    assert_eq "NODE_KB_FREE" $(to_upper_snake_case "nodeKBFree")
    assert_eq "NODE_MB_FREE" $(to_upper_snake_case "nodeMBFree")
    assert_eq "NODE_GB_FREE" $(to_upper_snake_case "nodeGBFree")
    assert_eq "NODE_TB_FREE" $(to_upper_snake_case "nodeTBFree")
}

ETEST_to_upper_snake_case_units_mixed()
{
    assert_eq "NODE_KB_FREE_WITH_MB_USED" $(to_upper_snake_case "nodeKBFreeWithMBUsed")
    assert_eq "KB_FREE_WITH_MB_USED_GB"   $(to_upper_snake_case "KBFreeWithMBUsedGB")
}
