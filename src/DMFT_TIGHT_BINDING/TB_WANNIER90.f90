module TB_WANNIER90
  USE TB_COMMON
  USE TB_BASIS
  USE TB_IO
  USE TB_EFERMI
  implicit none



  type :: w90_structure
     character(len=:),allocatable               :: w90_file
     integer                                    :: Num_wann=0
     integer                                    :: Nrpts=0
     character(len=20)                          :: DegFmt='(15I5)' !Ndegen format
     integer,allocatable,dimension(:)           :: Ndegen
     integer                                    :: Nlat=0
     integer                                    :: Norb=0   
     integer                                    :: Nspin=0
     integer,allocatable,dimension(:,:)         :: Rvec
     real(8),allocatable,dimension(:,:)         :: Rgrid
     complex(8),allocatable,dimension(:,:,:)    :: Hij
     complex(8),allocatable,dimension(:,:)      :: Hloc
     real(8)                                    :: Efermi
     complex(8),allocatable,dimension(:,:)      :: Zeta
     real(8),allocatable,dimension(:,:)         :: Self
     real(8),dimension(3)                       :: BZorigin
     logical                                    :: iRenorm=.false.
     logical                                    :: iFermi=.false.
     logical                                    :: verbose=.false.
     logical                                    :: hcheck=.false.
     logical                                    :: status=.false.
  end type w90_structure


  type(w90_structure) :: TB_w90


contains



  !< Setup the default_w90 structure with information coming from specified w90_file
  subroutine setup_w90(w90_file,nlat,nspin,norb,origin,verbose,Hcheck)
    character(len=*),intent(in) :: w90_file
    integer                     :: Nlat
    integer                     :: Norb
    integer                     :: Nspin
    real(8),optional            :: origin(:)
    logical,optional            :: verbose,Hcheck
    logical                     :: verbose_,hcheck_,master=.true.
    integer                     :: unitIO
    integer                     :: Num_wann
    integer                     :: Nrpts
    integer                     :: i,j,ir,a,b
    integer                     :: rx,ry,rz
    real(8)                     :: re,im,origin_(3)
    !
    origin_  = 0d0     ;if(present(origin))origin_(:size(origin))=origin
    verbose_ = .false. ;if(present(verbose))verbose_=verbose
    hcheck_  = .true.  ;if(present(hcheck))hcheck_=hcheck    
    !
    TB_w90%w90_file = str(w90_file)
    open(free_unit(unitIO),&
         file=TB_w90%w90_file,&
         status="old",&
         action="read")
    read(unitIO,*)                      !skip first line
    read(unitIO,*) Num_wann !Number of Wannier orbitals
    read(unitIO,*) Nrpts    !Number of Wigner-Seitz vectors
    !
    call delete_w90
    if(.not.set_eivec)stop "setup_w90: set_eivec=false"
    !
    !Massive structure allocation:
    TB_w90%Nlat  = Nlat
    TB_w90%Norb  = Norb
    TB_w90%Nspin = Nspin
    !
    TB_w90%Num_wann = Num_wann
    if(Num_wann /= TB_w90%Nlat*TB_w90%Norb)stop "setup_w90: Num_wann != Nlat*Norb"
    TB_w90%Nrpts    = Nrpts
    allocate(TB_w90%Ndegen(Nrpts))
    allocate(TB_w90%Rvec(Nrpts,3))
    allocate(TB_w90%Rgrid(Nrpts,3))
    allocate(TB_w90%Hij(num_wann*TB_w90%Nspin,num_wann*TB_w90%Nspin,Nrpts))
    allocate(TB_w90%Hloc(num_wann*TB_w90%Nspin,num_wann*TB_w90%Nspin))
    allocate(TB_w90%Zeta(num_wann*TB_w90%Nspin,num_wann*TB_w90%Nspin))
    allocate(TB_w90%Self(num_wann*TB_w90%Nspin,num_wann*TB_w90%Nspin))
    TB_w90%Ndegen   = 0
    TB_w90%Rvec     = 0
    TB_w90%Hij      = zero
    TB_w90%Hloc     = zero
    TB_w90%Zeta     = eye(num_wann*TB_w90%Nspin)
    TB_w90%Self     = 0d0
    TB_w90%Efermi   = 0d0
    TB_w90%verbose  = verbose_
    TB_w90%hcheck   = hcheck_
    TB_w90%BZorigin = origin_
    TB_w90%status   =.true.
    !
    !Read Ndegen from file: (as in original W90)
    read(unitIO,str(TB_w90%DegFmt))(TB_w90%Ndegen(ir),ir=1,Nrpts)
    !
    !Read w90 TB Hamiltonian (no spinup-spindw hybridizations assumed)
    do ir=1,Nrpts
       do i=1,Num_wann
          do j=1,Num_wann
             !
             read(unitIO,*)rx,ry,rz,a,b,re,im
             !
             TB_w90%Rvec(ir,:)  = [rx,ry,rz]
             TB_w90%Rgrid(ir,:) = rx*ei_x + ry*ei_y + rz*ei_z
             !
             TB_w90%Hij(a,b,ir)=dcmplx(re,im)
             if(TB_w90%Nspin==2)TB_w90%Hij(a+num_wann, b+num_wann, ir)=dcmplx(re,im)
             !
             if( all(TB_w90%Rvec(ir,:)==0) )then
                TB_w90%Hloc(a,b)=dcmplx(re,im)
                if(Nspin==2)TB_w90%Hloc(a+num_wann, b+num_wann)=dcmplx(re,im)
             endif
          enddo
       enddo
    enddo
    close(unitIO)
    !
    TB_w90%Hloc=slo2lso(TB_w90%Hloc,TB_w90%Nlat,TB_w90%Nspin,TB_w90%Norb)
    !
#ifdef _MPI    
    if(Check_MPI())master = get_master_MPI()
#endif
    if(master)then
       write(*,*)
       write(*,'(1A)')         "-------------- H_LDA --------------"
       write(*,'(A,I6)')      "  Number of Wannier functions:   ",TB_w90%num_wann
       write(*,'(A,I6)')      "  Number of Wigner-Seitz vectors:",TB_w90%nrpts
    endif
    !
  end subroutine setup_w90

  !< Setup the default_w90 structure with information coming from specified w90_file
  subroutine setup_w90_Hij(w90_file,nrpts,nlat,nspin,norb,origin,verbose,hcheck)
    character(len=*),intent(in) :: w90_file
    integer                     :: Nrpts
    integer                     :: Nlat
    integer                     :: Norb
    integer                     :: Nspin
    real(8),optional            :: origin(:)
    logical,optional            :: verbose,hcheck
    logical                     :: verbose_,hcheck_,master=.true.
    integer                     :: unitIO
    integer                     :: Num_wann,Nlso
    integer                     :: i,j,ir,a,b,len
    integer                     :: rx,ry,rz
    real(8)                     :: re,im,origin_(3)
    !
    origin_  = 0d0     ;if(present(origin))origin_(:size(origin))=origin
    verbose_ = .false. ;if(present(verbose))verbose_=verbose
    hcheck_  = .true.  ;if(present(hcheck))hcheck_=hcheck
    !
    TB_w90%w90_file = str(w90_file)
    !
    call delete_w90
    if(.not.set_eivec)stop "setup_w90: set_eivec=false"
    !
    !Massive structure allocation:
    TB_w90%Nlat  = Nlat
    TB_w90%Norb  = Norb
    TB_w90%Nspin = Nspin
    !
    Num_wann        = Nlat*Norb    
    TB_w90%Num_wann = Num_wann
    TB_w90%Nrpts    = Nrpts
    len = file_length(TB_w90%w90_file)
    if(Nrpts/=len/Num_wann/Num_wann)stop "setup_w90_Hij: wrong Nrpts"
    !
    allocate(TB_w90%Ndegen(Nrpts))
    allocate(TB_w90%Rvec(Nrpts,3))
    allocate(TB_w90%Rgrid(Nrpts,3))
    allocate(TB_w90%Hij(num_wann*TB_w90%Nspin,num_wann*TB_w90%Nspin,Nrpts))
    allocate(TB_w90%Hloc(num_wann*TB_w90%Nspin,num_wann*TB_w90%Nspin))
    allocate(TB_w90%Zeta(num_wann*TB_w90%Nspin,num_wann*TB_w90%Nspin))
    allocate(TB_w90%Self(num_wann*TB_w90%Nspin,num_wann*TB_w90%Nspin))
    TB_w90%Ndegen   = 1
    TB_w90%Rvec     = 0
    TB_w90%Hij      = zero
    TB_w90%Hloc     = zero
    TB_w90%Zeta     = eye(num_wann*TB_w90%Nspin)
    TB_w90%Self     = 0d0
    TB_w90%Efermi   = 0d0
    TB_w90%verbose  = verbose_
    TB_w90%hcheck   = hcheck_
    TB_w90%BZorigin = origin_
    TB_w90%status   =.true.
    !
    !Read w90 TB Hamiltonian (no spinup-spindw hybridizations assumed)
    open(free_unit(unitIO),&
         file=TB_w90%w90_file,&
         status="old",&
         action="read")
    rewind(unitIO)
    do ir=1,Nrpts
       do i=1,Num_wann
          do j=1,Num_wann
             !
             read(unitIO,*)rx,ry,rz,a,b,re,im
             !
             TB_w90%Rvec(ir,:)  = [rx,ry,rz]
             TB_w90%Rgrid(ir,:) = rx*ei_x + ry*ei_y + rz*ei_z
             !
             TB_w90%Hij(a,b,ir)=dcmplx(re,im)
             if(TB_w90%Nspin==2)TB_w90%Hij(a+num_wann, b+num_wann, ir)=dcmplx(re,im)
             !
             if( all(TB_w90%Rvec(ir,:)==0) )then
                TB_w90%Hloc(a,b)=dcmplx(re,im)
                if(Nspin==2)TB_w90%Hloc(a+num_wann, b+num_wann)=dcmplx(re,im)
             endif
          enddo
       enddo
    enddo
    close(unitIO)
    !
    TB_w90%Hloc=slo2lso(TB_w90%Hloc,TB_w90%Nlat,TB_w90%Nspin,TB_w90%Norb)
    !
#ifdef _MPI    
    if(Check_MPI())master = get_master_MPI()
#endif
    if(master)then
       write(*,*)
       write(*,'(1A)')         "-------------- H_LDA --------------"
       write(*,'(A,I6)')      "  Number of Wannier functions:   ",TB_w90%num_wann
       write(*,'(A,I6)')      "  Number of Wigner-Seitz vectors:",TB_w90%nrpts
    endif
    !
  end subroutine setup_w90_Hij




  subroutine delete_w90()
    if(.not.TB_w90%status)return
    TB_w90%Num_wann=0
    TB_w90%Nrpts=0
    TB_w90%DegFmt=''
    TB_w90%Nlat=0
    TB_w90%Norb=0
    TB_w90%Nspin=0
    TB_w90%Efermi=0d0
    TB_w90%verbose=.false.
    deallocate(TB_w90%w90_file)
    deallocate(TB_w90%Ndegen)
    deallocate(TB_w90%Rvec)
    deallocate(TB_w90%Rgrid)
    deallocate(TB_w90%Hij)
    deallocate(TB_w90%Hloc)
    TB_w90%status=.false.
  end subroutine delete_w90




  subroutine fix_w90file(file,nrpts,num_wann)
    character(len=*)             :: file
    character(len=:),allocatable :: file_bkp
    integer                      :: nrpts,num_wann,len
    integer                      :: ubkp,unit
    integer                      :: ir,i,j
    logical                      :: bool
    integer,allocatable          :: ndegen(:)
    integer                      :: rx,ry,rz,a,b
    real(8)                      :: re,im
    character(len=33)           :: header
    character(len=9)             :: cdate, ctime
    !
    inquire(file=reg(file),exist=bool)
    if(.not.bool)stop "TB_fix_w90: file not found"
    !
    len = file_length(reg(file))
    if(Nrpts/=len/Num_wann/Num_wann)stop "TB_fix_w90: wrong file length"
    !
    allocate(ndegen(Nrpts));Ndegen=1
    !
    file_bkp = reg(file)//".backup"
    !
    call system("cp -vf "//reg(file)//" "//reg(file_bkp))
    open(free_unit(ubkp),file=reg(file_bkp))
    open(free_unit(unit),file=reg(file))
    !
    call io_date(cdate,ctime)
    header = 'fixed on '//cdate//' at '//ctime
    write(unit,*)header ! Date and time
    write(unit,*)num_wann
    write(unit,*)nrpts
    write(unit,"(15I5)")(ndegen(i), i=1, nrpts)
    !
    do ir=1,Nrpts
       do i=1,Num_wann
          do j=1,Num_wann
             !
             read(ubkp,*)rx,ry,rz,a,b,re,im
             write(unit,"(5I5,2F12.6)")rx,ry,rz,a,b,re,im
          enddo
       enddo
    enddo
    close(ubkp)
    close(unit)
  contains
    !From Wannier90
    subroutine io_date(cdate, ctime)
      character(len=9), intent(out)   :: cdate
      character(len=9), intent(out)   :: ctime
      character(len=3), dimension(12) :: months
      data months/'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', &
           'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'/
      integer                         :: date_time(8)
      !
      call date_and_time(values=date_time)
      !
      write (cdate, '(i2,a3,i4)') date_time(3), months(date_time(2)), date_time(1)
      write (ctime, '(i2.2,":",i2.2,":",i2.2)') date_time(5), date_time(6), date_time(7)
    end subroutine io_date
  end subroutine fix_w90file




  subroutine Hloc_w90(Hloc)
    real(8),dimension(:,:) :: Hloc
    integer                :: Nlso
    Nlso = TB_w90%Nspin*TB_w90%Num_Wann
    call assert_shape(Hloc,[Nlso,Nlso],"Hloc_w90","Hloc")
    Hloc = TB_w90%Hloc
  end subroutine Hloc_w90



  !< generate an internal function to be called in the building procedure
  function w90_hk_model(kvec,N) result(Hk)
    real(8),dimension(:)      :: kvec
    integer                   :: N
    complex(8),dimension(N,N) :: Hk,Hk_f
    complex(8)                :: kExp
    integer                   :: nDim,Nso
    integer                   :: i,j,ir
    real(8)                   :: rvec(size(kvec)),rdotk,WSdeg
    !
    if(.not.TB_w90%status)stop "w90_hk_model: TB_w90 was not setup"
    !
    nDim = size(kvec)
    Nso  = TB_w90%Nspin*TB_w90%Num_wann
    if(Nso /= N )stop "w90_hk_model: Nso != N"
    Hk = zero
    do ir=1,TB_w90%Nrpts
       Rvec  = TB_w90%Rgrid(ir,:nDim)
       rdotk = dot_product(Kvec,Rvec)
       kExp  = dcmplx(cos(rdotk),-sin(rdotk))
       WSdeg = TB_w90%Ndegen(ir)
       !
       Hk = Hk+TB_w90%Hij(:,:,ir)*kExp/WSdeg
    enddo
    !
    where(abs(Hk)<1d-9)Hk=zero
    !
    if(TB_w90%hcheck)call herm_check(Hk)
    if(TB_w90%Ifermi)Hk = Hk - TB_w90%Efermi*eye(N)
    !
    if(TB_w90%Irenorm)then
       Hk   = Hk - TB_w90%Hloc
       Hk_f = (TB_w90%Zeta .x. Hk) .x. TB_w90%Zeta
       Hk   = Hk_f + TB_w90%Hloc + TB_w90%Self
    endif
    !
  end function w90_hk_model


  subroutine FermiLevel_w90(Nkvec,filling,Ef)
    integer,dimension(:),intent(in)          :: Nkvec
    real(8)                                  :: filling,Efermi
    real(8),optional                         :: Ef
    complex(8),dimension(:,:,:),allocatable  :: Hk
    integer                                  :: Nlso,Nk
    mpi_master=.false.
#ifdef _MPI    
    if(check_MPI())then
       mpi_master= get_master_MPI()
    else
       mpi_master=.true.
    endif
#else
    mpi_master=.true.
#endif
    if(TB_w90%Ifermi)return
    Nlso = TB_w90%Nspin*TB_w90%Num_Wann
    Nk   = product(Nkvec)
    allocate(Hk(Nlso,Nlso,Nk))
    call build_hk_w90(Hk,Nlso,Nkvec)
    call TB_FermiLevel(Hk,filling,Efermi,TB_w90%Nspin,TB_w90%verbose)
    TB_w90%Efermi = Efermi
    if(present(Ef))Ef=Efermi
    TB_w90%Ifermi=.true.
  end subroutine FermiLevel_w90



  subroutine Zeta_w90_vector(zeta)
    real(8),dimension(:)          :: zeta
    real(8),dimension(size(zeta)) :: sq_zeta
    integer                       :: Nlso
    Nlso = TB_w90%Nspin*TB_w90%Num_Wann
    call assert_shape(zeta,[Nlso],"Zeta_w90","zeta")
    sq_zeta     = sqrt(zeta)
    TB_w90%zeta = diag(sq_zeta)
    TB_w90%Irenorm=.true.
  end subroutine Zeta_w90_vector
  !
  subroutine Zeta_w90_matrix(zeta)
    real(8),dimension(:,:) :: zeta
    integer                :: Nlso
    Nlso = TB_w90%Nspin*TB_w90%Num_Wann
    call assert_shape(zeta,[Nlso,Nlso],"Zeta_w90","zeta")  
    TB_w90%zeta = sqrt(zeta)
    TB_w90%Irenorm=.true.
  end subroutine Zeta_w90_matrix



  subroutine Self0_w90(Self0)
    real(8),dimension(:,:) :: self0
    integer                :: Nlso
    Nlso = TB_w90%Nspin*TB_w90%Num_Wann
    call assert_shape(self0,[Nlso,Nlso],"Self0_w90","Self0")  
    TB_w90%Self = Self0
    TB_w90%Irenorm=.true.
  end subroutine Self0_w90







  subroutine build_hk_w90(Hk,Nlso,Nkvec,Kpts_grid,wdos)
    integer                                                :: Nlso
    integer,dimension(:),intent(in)                        :: Nkvec
    complex(8),dimension(Nlso,Nlso,product(Nkvec))         :: Hk,haux
    !
    real(8),dimension(product(Nkvec),size(Nkvec)),optional :: Kpts_grid ![Nk][Ndim]
    logical,optional                                       :: wdos
    logical                                                :: wdos_
    !
    real(8),dimension(product(Nkvec),size(Nkvec))          :: kgrid ![Nk][Ndim]
    integer                                                :: Nk
    logical                                                :: IOfile
    integer                                                :: i,j,ik
    !
    !MPI setup:
#ifdef _MPI    
    if(check_MPI())then
       mpi_size  = get_size_MPI()
       mpi_rank =  get_rank_MPI()
       mpi_master= get_master_MPI()
    else
       mpi_size=1
       mpi_rank=0
       mpi_master=.true.
    endif
#else
    mpi_size=1
    mpi_rank=0
    mpi_master=.true.
#endif
    !
    wdos_=.false.;if(present(wdos))wdos_=wdos
    !
    Nk =product(Nkvec)
    !
    if(.not.TB_w90%status)stop "build_hk_w90: TB_w90 structure not allocated. Call setup_w90 first."
    !
    call build_kgrid(Nkvec,Kgrid,.true.,TB_w90%BZorigin) !check bk_1,2,3 vectors have been set
    if(present(Kpts_grid))Kpts_grid=Kgrid
    !
    Haux=zero
    do ik=1+mpi_rank,Nk,mpi_size
       haux(:,:,ik) = w90_hk_model(Kgrid(ik,:),Nlso)
    enddo
#ifdef _MPI
    if(check_MPI())then
       Hk = zero
       call AllReduce_MPI(MPI_COMM_WORLD,Haux,Hk)
    else
       Hk = Haux
    endif
#else
    Hk = Haux
#endif
    !
    if(wdos_)then
       allocate(dos_Greal(TB_w90%Nlat,TB_w90%Nspin,TB_w90%Nspin,TB_w90%Norb,TB_w90%Norb,dos_Lreal))
       allocate(dos_wtk(Nk))
       dos_wtk=1d0/Nk
#ifdef _MPI
       if(check_MPI())then
          call dmft_gloc_realaxis(MPI_COMM_WORLD,Hk,dos_wtk,dos_Greal,zeros(TB_w90%Nlat,TB_w90%Nspin,TB_w90%Nspin,TB_w90%Norb,TB_w90%Norb,dos_Lreal))
       else
          call dmft_gloc_realaxis(Hk,dos_wtk,dos_Greal,zeros(TB_w90%Nlat,TB_w90%Nspin,TB_w90%Nspin,TB_w90%Norb,TB_w90%Norb,dos_Lreal))
       endif
#else
       call dmft_gloc_realaxis(Hk,dos_wtk,dos_Greal,zeros(TB_w90%Nlat,TB_w90%Nspin,TB_w90%Nspin,TB_w90%Norb,TB_w90%Norb,dos_Lreal))
#endif
       if(mpi_master)call dmft_print_gf_realaxis(dos_Greal,trim(dos_file),iprint=1)
    endif
  end subroutine build_hk_w90




  subroutine build_hk_w90_path(Hk,Nlso,Kpath,Nkpath)
    integer                                                   :: Nlso
    real(8),dimension(:,:)                                    :: kpath ![Npts][Ndim]
    integer                                                   :: Nkpath
    integer                                                   :: Npts,Nktot
    complex(8),dimension(Nlso,Nlso,(size(kpath,1)-1)*Nkpath)  :: Hk,haux
    !
    real(8),dimension((size(kpath,1)-1)*Nkpath,size(kpath,2)) :: kgrid
    integer                                                   :: Nk
    logical                                                   :: IOfile
    integer                                                   :: i,j,ik
    !
    !MPI setup:
#ifdef _MPI    
    if(check_MPI())then
       mpi_size  = get_size_MPI()
       mpi_rank =  get_rank_MPI()
       mpi_master= get_master_MPI()
    else
       mpi_size=1
       mpi_rank=0
       mpi_master=.true.
    endif
#else
    mpi_size=1
    mpi_rank=0
    mpi_master=.true.
#endif
    !
    if(.not.TB_w90%status)stop "build_hk_w90_path: TB_w90 structure not allocated. Call setup_w90 first."
    !
    Npts  =  size(kpath,1)          !# of k-points along the path
    Nktot = (Npts-1)*Nkpath
    !
    call kgrid_from_path_grid(kpath,Nkpath,kgrid)
    !
    Haux=zero
    do ik=1+mpi_rank,Nktot,mpi_size
       haux(:,:,ik) = w90_hk_model(Kgrid(ik,:),Nlso)
    enddo
#ifdef _MPI
    if(check_MPI())then
       Hk = zero
       call AllReduce_MPI(MPI_COMM_WORLD,Haux,Hk)
    else
       Hk = Haux
    endif
#else
    Hk = Haux
#endif
    !
  end subroutine build_hk_w90_path








  !OLD STUFF:
  !< read the real space hopping matrix from Wannier90 output and create H(k)
  include "w90hr/tight_binding_build_hk_from_w90hr.f90"
#ifdef _MPI
  include "w90hr/tight_binding_build_hk_from_w90hr_mpi.f90"
#endif
  !< read the real space lattice position and compute the space integrals
  !          <t2g| [x,y,z] |t2g> using atomic orbital as a subset.
  include "w90hr/dipole_w90hr.f90"
#ifdef _MPI
  include "w90hr/dipole_w90hr_mpi.f90"
#endif

#ifdef _MPI
  function MPI_Get_size(comm) result(size)
    integer :: comm
    integer :: size,ierr
    call MPI_Comm_size(comm,size,ierr)
  end function MPI_Get_size

  function MPI_Get_rank(comm) result(rank)
    integer :: comm
    integer :: rank,ierr
    call MPI_Comm_rank(comm,rank,ierr)
  end function MPI_Get_rank

  function MPI_Get_master(comm) result(master)
    integer :: comm
    logical :: master
    integer :: rank,ierr
    call MPI_Comm_rank(comm,rank,ierr)
    master=.false.
    if(rank==0)master=.true.
  end function MPI_Get_master
#endif




  subroutine herm_check(A)
    complex(8),intent(in) ::   A(:,:)
    integer               ::   row,col,i,j
    row=size(A,1)
    col=size(A,2)
    do i=1,col
       do j=1,row
          if(abs(A(i,j))-abs(A(j,i)) .gt. 1d-6)then
             write(*,'(1A)') "--> NON HERMITIAN MATRIX <--"
             write(*,'(2(1A7,I3))') " row: ",i," col: ",j
             write(*,'(1A)') "  A(i,j)"
             write(*,'(2F22.18)') real(A(i,j)),aimag(A(i,j))
             write(*,'(1A)') "  A(j,i)"
             write(*,'(2F22.18)') real(A(j,i)),aimag(A(j,i))
             stop
          endif
       enddo
    enddo
  end subroutine herm_check



END MODULE TB_WANNIER90











