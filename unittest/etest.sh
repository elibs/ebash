

ETEST_etest_no_cross_contamination_A()
{
    CROSS_CONTAMINATION_A=1
    expect_empty ${CROSS_CONTAMINATION_B}
}

ETEST_etest_no_cross_contamination_B()
{
    CROSS_CONTAMINATION_B=20
    expect_empty ${CROSS_CONTAMINATION_A}
}
