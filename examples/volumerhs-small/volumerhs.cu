#include <cuda.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <math.h>

// to build on Titan V:
//   nvcc -arch=sm_70 --ptxas-options=-v -o vanilladeriv vanilladeriv.cu;

#ifdef USE_DOUBLE
#define dfloat double
#else
#define dfloat float
#endif

#ifndef POLYNOMIAL_ORDER
#define POLYNOMIAL_ORDER 4
#endif

// note the order of the fields below is also assumed in the code.
const int _nstate = 5;

const int _R = 0, _U  = 1, _V  = 2, _W = 3, _E = 4;

const int _nvgeo = 14;
const int _XIx   = 0;
const int _ETAx  = 1;
const int _ZETAx = 2;
const int _XIy   = 3;
const int _ETAy  = 4;
const int _ZETAy = 5;
const int _XIz   = 6;
const int _ETAz  = 7;
const int _ZETAz = 8;
const int _MJ    = 9;
const int _MJI   = 10;
const int _x     = 11;
const int _y     = 12;
const int _z     = 13;

#define grav  ((dfloat) 9.81)
#define gdm1  ((dfloat) 0.4)


template <int Nq, int Np, int nvar>
  __global__ void volumerhs(dfloat * __restrict__ rhs,
                            const dfloat * __restrict__ Q,
                            const dfloat * __restrict__ vgeo,
                            const dfloat gravity,
                            const dfloat * __restrict__ D,
                            const int nelem){

  __shared__ dfloat s_D[Nq][Nq];
  __shared__ dfloat s_F[Nq][Nq][_nstate];
  __shared__ dfloat s_G[Nq][Nq][_nstate];

  dfloat r_rhsR[Nq];
  dfloat r_rhsU[Nq];
  dfloat r_rhsV[Nq];
  dfloat r_rhsW[Nq];
  dfloat r_rhsE[Nq];

  int e = blockIdx.x;
  int j = threadIdx.y;
  int i = threadIdx.x;

  s_D[j][i] = D[j*Nq+i];

#pragma unroll Nq
  for(int k=0;k<Nq;++k){
    r_rhsR[k] = 0;
    r_rhsU[k] = 0;
    r_rhsV[k] = 0;
    r_rhsW[k] = 0;
    r_rhsE[k] = 0;
  }

#pragma unroll Nq
  for(int k=0;k<Nq;++k){

    __syncthreads();

    // Load values will need into registers
    int gid = i + j*Nq + k*Nq*Nq + e*Np*_nvgeo;

    dfloat MJ = vgeo[gid + _MJ*Np];
    dfloat XIx = vgeo[gid + _XIx*Np];
    dfloat XIy = vgeo[gid + _XIy*Np];
    dfloat XIz = vgeo[gid + _XIz*Np];
    dfloat ETAx = vgeo[gid + _ETAx*Np];
    dfloat ETAy = vgeo[gid + _ETAy*Np];
    dfloat ETAz = vgeo[gid + _ETAz*Np];
    dfloat ZETAx = vgeo[gid + _ZETAx*Np];
    dfloat ZETAy = vgeo[gid + _ZETAy*Np];
    dfloat ZETAz = vgeo[gid + _ZETAz*Np];
    dfloat z = vgeo[gid +  _z*Np];


    int qid = i + j*Nq + k*Nq*Nq + e*Np*nvar;

    dfloat R = Q[qid + _R*Np];
    dfloat U = Q[qid + _U*Np];
    dfloat V = Q[qid + _V*Np];
    dfloat W = Q[qid + _W*Np];
    dfloat E = Q[qid + _E*Np];

    dfloat P = gdm1*(E - (U*U + V*V + W*W)/(2*R) - R*gravity*z);

    dfloat Rinv = 1 / R;

    dfloat fluxR_x = U;
    dfloat fluxU_x = Rinv * U * U + P;
    dfloat fluxV_x = Rinv * U * V;
    dfloat fluxW_x = Rinv * U * W;
    dfloat fluxE_x = Rinv * U * (E + P);

    dfloat fluxR_y = V;
    dfloat fluxU_y = Rinv * V * U;
    dfloat fluxV_y = Rinv * V * V + P;
    dfloat fluxW_y = Rinv * V * W;
    dfloat fluxE_y = Rinv * V * (E + P);

    dfloat fluxR_z = W;
    dfloat fluxU_z = Rinv * W * U;
    dfloat fluxV_z = Rinv * W * V;
    dfloat fluxW_z = Rinv * W * W + P;
    dfloat fluxE_z = Rinv * W * (E + P);

    s_F[i][j][ _R] = MJ * (XIx * fluxR_x + XIy * fluxR_y + XIz * fluxR_z);
    s_F[i][j][ _U] = MJ * (XIx * fluxU_x + XIy * fluxU_y + XIz * fluxU_z);
    s_F[i][j][ _V] = MJ * (XIx * fluxV_x + XIy * fluxV_y + XIz * fluxV_z);
    s_F[i][j][ _W] = MJ * (XIx * fluxW_x + XIy * fluxW_y + XIz * fluxW_z);
    s_F[i][j][ _E] = MJ * (XIx * fluxE_x + XIy * fluxE_y + XIz * fluxE_z);

    s_G[i][j][ _R] = MJ * (ETAx * fluxR_x + ETAy * fluxR_y + ETAz * fluxR_z);
    s_G[i][j][ _U] = MJ * (ETAx * fluxU_x + ETAy * fluxU_y + ETAz * fluxU_z);
    s_G[i][j][ _V] = MJ * (ETAx * fluxV_x + ETAy * fluxV_y + ETAz * fluxV_z);
    s_G[i][j][ _W] = MJ * (ETAx * fluxW_x + ETAy * fluxW_y + ETAz * fluxW_z);
    s_G[i][j][ _E] = MJ * (ETAx * fluxE_x + ETAy * fluxE_y + ETAz * fluxE_z);

    dfloat r_HR = MJ * (ZETAx * fluxR_x + ZETAy * fluxR_y + ZETAz * fluxR_z);
    dfloat r_HU = MJ * (ZETAx * fluxU_x + ZETAy * fluxU_y + ZETAz * fluxU_z);
    dfloat r_HV = MJ * (ZETAx * fluxV_x + ZETAy * fluxV_y + ZETAz * fluxV_z);
    dfloat r_HW = MJ * (ZETAx * fluxW_x + ZETAy * fluxW_y + ZETAz * fluxW_z);
    dfloat r_HE = MJ * (ZETAx * fluxE_x + ZETAy * fluxE_y + ZETAz * fluxE_z);

    // one shared access per 10 flops
#pragma unroll Nq
    for(int n=0;n<Nq;++n){
      dfloat  Dkn = s_D[k][n];

      r_rhsR[n] += Dkn * r_HR;
      r_rhsU[n] += Dkn * r_HU;
      r_rhsV[n] += Dkn * r_HV;
      r_rhsW[n] += Dkn * r_HW;
      r_rhsE[n] += Dkn * r_HE;
    }

    r_rhsW[k] -= MJ * R * gravity;

    __syncthreads();

    // loop of XI-grid lines
#pragma unroll Nq
    for(int n=0;n<Nq;++n){
      dfloat Dni = s_D[n][i];
      dfloat Dnj = s_D[n][j];

      r_rhsR[k] += Dni * s_F[n][j][_R];
      r_rhsR[k] += Dnj * s_G[i][n][_R];

      r_rhsU[k] += Dni * s_F[n][j][_U];
      r_rhsU[k] += Dnj * s_G[i][n][_U];

      r_rhsV[k] += Dni * s_F[n][j][_V];
      r_rhsV[k] += Dnj * s_G[i][n][_V];

      r_rhsW[k] += Dni * s_F[n][j][_W];
      r_rhsW[k] += Dnj * s_G[i][n][_W];

      r_rhsE[k] += Dni * s_F[n][j][_E];
      r_rhsE[k] += Dnj * s_G[i][n][_E];
    }
  }

#pragma unroll Nq
  for(int k=0;k<Nq;++k){
    int gid = i + j*Nq + k*Nq*Nq + e*Np*_nvgeo;
    dfloat MJI = vgeo[gid +  _MJI*Np];

    int qid = i + j*Nq + k*Nq*Nq + e*Np*nvar;

    rhs[qid+_U*Np] += MJI*r_rhsU[k];
    rhs[qid+_V*Np] += MJI*r_rhsV[k];
    rhs[qid+_W*Np] += MJI*r_rhsW[k];
    rhs[qid+_R*Np] += MJI*r_rhsR[k];
    rhs[qid+_E*Np] += MJI*r_rhsE[k];
  }
}

void randArray(int N, dfloat base, dfloat range, dfloat **q, dfloat **c_q){

  *q = (dfloat*) calloc(N, sizeof(dfloat));
  cudaMalloc(c_q, N*sizeof(dfloat));

  for(int n=0;n<N;++n){
    q[0][n] = base + drand48()*range;
  }

  cudaMemcpy(c_q[0], q[0], N*sizeof(dfloat), cudaMemcpyHostToDevice);

}

int main(int argc, char **argv){

  srand48(1234);

  const int N = POLYNOMIAL_ORDER;
  const int nelem = 4000;

  const int Nq = N+1;
  const int Np = Nq*Nq*Nq;

  const int Ntotal = Np*nelem*_nstate;

  dfloat *Q, *c_Q;
  randArray(Ntotal, 0., 1., &Q, &c_Q);

  for(int e=0;e<nelem;++e){
    for(int n=0;n<Np;++n){
      int idR = n + _R*Np + e*_nstate*Np;
      int idE = n + _E*Np + e*_nstate*Np;

      Q[idR] += 2.;
      Q[idE] += 20.;

    }
  }

  cudaMemcpy(c_Q, Q, nelem*_nstate*Np*sizeof(dfloat), cudaMemcpyHostToDevice);

  const int Gtotal = Np*nelem*_nvgeo;

  dfloat *vgeo, *c_vgeo;
  randArray(Gtotal, 0, 1., &vgeo, &c_vgeo);

  // Make sure the entries of the mass matrix satisfy the inverse relation
  for(int e=0;e<nelem;++e){
    for(int n=0;n<Np;++n){
      int idMJ = n + _MJ*Np + e*_nvgeo*Np;
      int idMJI = n + _MJI*Np + e*_nvgeo*Np;

      vgeo[idMJ] += 3;
      vgeo[idMJI] = 1./vgeo[idMJ];

    }
  }
  cudaMemcpy(c_vgeo, vgeo, nelem*_nvgeo*Np*sizeof(dfloat), cudaMemcpyHostToDevice);

  dfloat *D, *c_D;
  randArray(Nq*Nq, 1., 1., &D, &c_D);

  dfloat *rhs, *c_rhs;

  srand48(1234);
  randArray(Ntotal, 1., 1., &rhs, &c_rhs);

  dim3 G(nelem,1,1);
  dim3 B2(Nq,Nq,Nq);
  dim3 B3(Nq,Nq,1);

  volumerhs<Nq, Np, _nstate> <<< G, B3 >>> (c_rhs, c_Q, c_vgeo, grav, c_D, nelem);

  cudaDeviceSynchronize();

  exit(0);
  return 0;
}
