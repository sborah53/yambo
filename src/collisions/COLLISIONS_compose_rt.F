!
!        Copyright (C) 2000-2019 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details): CA AM DS
!
! This file is distributed under the terms of the GNU
! General Public License. You can redistribute it and/or
! modify it under the terms of the GNU General Public
! License as published by the Free Software Foundation;
! either version 2, or (at your option) any later version.
!
! This program is distributed in the hope that it will
! be useful, but WITHOUT ANY WARRANTY; without even the
! implied warranty of MERCHANTABILITY or FITNESS FOR A
! PARTICULAR PURPOSE.  See the GNU General Public License
! for more details.
!
! You should have received a copy of the GNU General Public
! License along with this program; if not, write to the Free
! Software Foundation, Inc., 59 Temple Place - Suite 330,Boston,
! MA 02111-1307, USA or visit http://www.gnu.org/copyleft/gpl.txt.
!
subroutine COLLISIONS_compose_rt(dG_in)
 !
 ! HF/SEX(state) = - (0.,1.) * \sum_{n,n',q} COLLISIONS(n,n',q,state) x G_lesser(n,n',k-q)
 ! 
 use pars,             ONLY:SP,cZERO,cI
 use drivers,          ONLY:l_sc_fock,l_sc_coh,l_sc_sex,l_sc_exx,l_sc_hartree
 use collision_ext,    ONLY:HXC_COLL_element,COLL_bands,HXC_collisions
 use electrons,        ONLY:spin
 use R_lattice,        ONLY:nXkibz
 use parallel_m,       ONLY:PP_redux_wait,PAR_COM_Xk_ibz_INDEX,PAR_COM_Q_INDEX,&
&                           PAR_IND_Xk_ibz,PAR_IND_Bp_mat
 use hamiltonian,      ONLY:B_mat_index
 use real_time,        ONLY:RT_nk,RT_ibz_coo,RT_Nk_ibz,RT_Vnl_xc,RT_bands
 use timing_m,         ONLY:timing
 !
 implicit none
 !
 complex(SP), intent(in)   :: dG_in(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),RT_nk)
 !
 ! Work Space
 !
 integer           :: i_coll,i_comp,i_coll_mem,i_spin,i_n,i_m,i_kmq,ib,ibp,i_k,i_k_RT
 complex(SP)       :: G_avg(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),nXkibz)
 !
 if(.not.l_sc_fock.and..not.l_sc_coh.and..not.l_sc_sex.and..not.l_sc_exx.and..not.l_sc_hartree) return
 !
 call timing('COLLISIONS (compose)',OPR='start')
 !
 G_avg=cZERO
 !
 do i_k=1,nXkibz
   !
   if (.not.PAR_IND_Xk_ibz%element_1D(i_k) ) cycle
   !
   do i_k_RT=RT_ibz_coo(i_k,1),RT_ibz_coo(i_k,2)
     G_avg(:,:,i_k)=G_avg(:,:,i_k)+dG_in(:,:,i_k_RT)
   enddo
   !
   ! The 1/real(RT_Nk_ibz(i_k),SP) factor is needed here because I'm integrating
   ! over kmq. With the DbGd the size of the integrating factor has to be reduced
   ! 
   G_avg(:,:,i_k)=G_avg(:,:,i_k)/real(RT_Nk_ibz(i_k),SP)/real(PAR_COM_Q_INDEX%n_CPU)
   !
 enddo
 !
 call timing('COLLISIONS (compose)',OPR='stop')
 !
 call timing('COLLISIONS (redux)',OPR='start')
 !
 call PP_redux_wait(G_avg,COMM=PAR_COM_Xk_ibz_INDEX%COMM)
 !
 call timing('COLLISIONS (redux)',OPR='stop')
 !
 call timing('COLLISIONS (compose)',OPR='start')
 !
 RT_Vnl_xc=cZERO
 !
 do i_coll=1,HXC_collisions%N
   !
   if (.not.HXC_collisions%PAR_IND%element_1D(i_coll)) cycle
   !
   i_k       =HXC_collisions%state(i_coll,3)
   i_n       =HXC_collisions%state(i_coll,1)
   i_m       =HXC_collisions%state(i_coll,2)
   i_spin    =HXC_collisions%state(i_coll,4)
   i_coll_mem=HXC_collisions%PAR_map(i_coll)
   !
   ! If the COLLISIONS are read from a DB with more bands than RT_bands:
   !
   if (i_n<RT_bands(1).or.i_n>RT_bands(2)) cycle
   if (i_m<RT_bands(1).or.i_m>RT_bands(2)) cycle
   !
   i_comp=0
   !
   do i_kmq=1,nXkibz
     !
     do ibp=COLL_bands(1),COLL_bands(2)
       do ib=COLL_bands(1),COLL_bands(2)
         !
         if (HXC_COLL_element(i_coll_mem)%table(ib,ibp,i_kmq)=='f') cycle
         !
         i_comp=i_comp+1
         !
         if (.not.PAR_IND_Bp_mat%element_1D( B_mat_index(ib,ibp,COLL_bands) ) ) cycle
         !
         RT_Vnl_xc(i_n,i_m,i_k,i_spin)=RT_Vnl_xc(i_n,i_m,i_k,i_spin) &
&                                      -cI*HXC_COLL_element(i_coll_mem)%v_c(i_comp)*G_avg(ib,ibp,i_kmq)
         !
       enddo
     enddo
     !
   enddo
   !
 enddo
 !
 ! All 2 All
 !===========
 !
 call PP_redux_wait(RT_Vnl_xc)
 !
 ! Symmetrization
 !================
 do i_k=1,nXkibz
   do i_n=COLL_bands(1),COLL_bands(2)
     RT_Vnl_xc(i_n,i_n,i_k,:)= real(RT_Vnl_xc(i_n,i_n,i_k,:))
     do i_m=i_n+1,COLL_bands(2)
       RT_Vnl_xc(i_m,i_n,i_k,:)=conjg(RT_Vnl_xc(i_n,i_m,i_k,:))
     enddo
   enddo
 enddo
 !
 call timing('COLLISIONS (compose)',OPR='stop')
 !
end subroutine COLLISIONS_compose_rt
