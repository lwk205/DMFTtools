file(GLOB DMFT_WEISS_FIELD_LOCAL_SRC
  DMFT_WEISS_FIELD.f90
  )
SET(DMFT_WEISS_FIELD_src ${DMFT_WEISS_FIELD_LOCAL_SRC})
ADD_LIBRARY(DMFT_WEISS_FIELDLIB OBJECT ${DMFT_WEISS_FIELD_src})
ADD_DEPENDENCIES(DMFT_WEISS_FIELDLIB DMFT_CTRL_VARSLIB)
